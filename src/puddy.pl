#! /usr/local/bin/perl -Tw
#
# Copyright 2019, Verizon Media
#
# Licensed under the terms of the BSD 3-Clause License.
# See LICENSE file for terms.
#
# This tool allows you to query a number of different
# resolvers to compare whether results are uniform
# across the internet.

use 5.008;

use strict;
use File::Basename;
use Getopt::Long;
use IO::Socket::INET6;
use JSON;
use Locale::Country qw(code2country);
use List::Util 'shuffle';
use Net::DNS;
use Net::DNS::Parameters qw(typebyval rcodebyval);
use Net::IP;
use Net::Netmask;
use Parallel::ForkManager;
use Socket qw(PF_INET PF_INET6 inet_ntoa inet_pton);
use URI::Escape;

Getopt::Long::Configure("bundling");

# We untaint the whole path, because we do allow the
# user to change it to point to a curl(1) of their
# preference.
my $safepath = $ENV{PATH};
if ($safepath =~ m/(.*)/) {
	$ENV{PATH} = $1;
}

delete($ENV{CDPATH});
delete($ENV{ENV});

###
### Constants
###

use constant EXIT_FAILURE => 1;
use constant EXIT_SUCCESS => 0;

use constant PUBLIC_URL => "https://public-dns.info/nameservers.txt";
use constant CIPGR_URL => "http://services.ce3c.be/ciprg/";

use constant VERSION => 1.2;

###
### Globals
###

# We start with a small default; we may bump this up
# based on 'ulimit -n' below.
my $CONCURRENCY = 8;
my %OPTS;
my $PROGNAME = basename($0);
my $RETVAL = 0;

my %RESULTS;

my $EDNS_CLIENT_SUBNET;

my %DOH = (
		"https://cloudflare-dns.com/dns-query?" => "Cloudflare",
		"https://doh.li/dns-query?"		=> "doh.li",
		"https://doh.dns.sb/dns-query?"		=> "DNS.SB",
		"https://dns.google/resolve?"		=> "Google",
		"https://doh.netweaver.uk/dns-query?"	=> "Netweaver",
		"https://9.9.9.9:5053/dns-query?"	=> "Quad9",
		"https://doh.securedns.eu/dns-query?"	=> "SecureDNS.eu",
	  );

my %RESOLVERS = (
			"ipv4" => {
				"1.0.0.1"		=> "Cloudflare",
				"1.1.1.1"		=> "Cloudflare",
				"8.8.4.4"		=> "Google",
				"8.8.8.8"		=> "Google",
				"9.9.9.9"		=> "Quad9",
				"74.82.42.42"		=> "Hurricane Electric",
				"208.67.220.220"	=> "OpenDNS",
				"208.67.222.222"	=> "OpenDNS",
				},
			"ipv6" => {
				"2001:470:20::2"	=> "Hurricane Electric",
				"2001:4860:4860::8844"	=> "Google",
				"2001:4860:4860::8888"	=> "Google",
				"2606:4700:4700::1001"	=> "Cloudflare",
				"2606:4700:4700::1111"	=> "Cloudflare",
				"2620:0:ccc::2"		=> "OpenDNS",
				"2620:0:ccd::2"		=> "OpenDNS",
				"2620:fe::fe"		=> "Quad9",
				},
		);

###
### Subroutines
###


sub checkPTR() {
	if (inet_pton(PF_INET, $OPTS{'query'}) || inet_pton(PF_INET6, $OPTS{'query'})) {
		if (scalar(keys(%{$OPTS{'wanted'}}))) {
			if ((scalar(@{$OPTS{'types'}}) > 1) || !$OPTS{'wanted'}{'PTR'}) {
				error("Unable to lookup any RRs of types other than PTR for IP addresses.", EXIT_FAILURE);
				# NOTREACHED
			}
		}
		my $ip = new Net::IP($OPTS{'query'});
		$OPTS{'query'} = $ip->reverse_ip();
		my @types = ( "PTR" );
		$OPTS{'types'} = \@types;
	} elsif (grep(/PTR/, @{$OPTS{'types'}})) {
		error("You can't lookup a PTR for something that's not an IP address.", EXIT_FAILURE);
		# NOTREACHED
	}
}

sub error($;$) {
	my ($msg, $err) = @_;

	if (!$OPTS{'q'}) {
		print STDERR "$PROGNAME: $msg\n";
	}
	$RETVAL++;

	if ($err) {
		exit($err);
		# NOTREACHED
	}
}

sub getCountryNetblocks() {
	my $c = lc($OPTS{'country'});
	# Catch a few common cases, even if some of those
	# are not correct or may infuriate people.
	if ($c eq "usa") {
		$c = "United States";
	} elsif ($c eq "russia") {
		$c = "Russian Federation";
	} elsif (($c eq "england") || ($c eq "uk")) {
		$c = "united kingdom";
	} elsif ($c eq "north korea") {
		$c = "Korea Democratic People's Republic Of";
	} elsif ($c eq "syria") {
		$c = "syrian arab republic";
	} elsif ($c eq "taiwan") {
		$c = "TAIWAN; REPUBLIC OF CHINA (ROC)";
	} elsif ($c eq "vietnam") {
		$c = "viet nam";
	}

	if ($c eq "none") {
		$EDNS_CLIENT_SUBNET = "0.0.0.0/0";
		return
	}

	# We try to look up the CC; if that fails,
	# let's pretend the arg is a country name
	# and send it over to the service.
	my $country = code2country($c);
	if (!$country) {
		$country = $c;
	}
	verbose("Looking up netblocks allocated to $country...");

	my $query = "?format=shareaza&countrys=" . uri_escape($country);
	my $url = CIPGR_URL . $query;
	verbose("Fetching '$url'...", 2);

	my @country_netblocks;
	my @cmd = ( "curl", "-s", $url);
	open(my $out, "-|", @cmd) or error("Unable to open pipe from '".
						join(" ", @cmd) . "': $!", EXIT_FAILURE);
	foreach my $line (<$out>) {
		if ($line =~ m/.*address="(.*)" action.*mask="(.*)" comment="(.*)"/) {
			my $ip = $1;
			my $mask = $2;
			my $country = $3;
			my $block;
			eval {
				local $SIG{__WARN__} = sub {};
				$block = Net::Netmask->new($ip, $mask);
			};
			if (!$block || $block->{'ERROR'}) {
				next;
			}

			push(@country_netblocks, "".$block);
		}
	}

	if (!scalar(@country_netblocks)) {
		error("Unable to determine a netblock for '" . $OPTS{'country'} ."'.", EXIT_FAILURE);
	}
	$EDNS_CLIENT_SUBNET = $country_netblocks[rand(@country_netblocks)];
}

sub init() {
	my ($ok);

	if (!scalar(@ARGV)) {
		error("I have nothing to do.  Try -h.", EXIT_FAILURE);
		# NOTREACHED
	}

	$ok = GetOptions(
			"one|1"		=> \$OPTS{'1'},
			"ipv4|4"	=> \$OPTS{'4'},
			"ipv6|6"	=> \$OPTS{'6'},
			"version|V"	=> sub { print "$PROGNAME Version " . VERSION . "\n"; exit(EXIT_SUCCESS); },
			"country|c=s"	=> \$OPTS{'country'},
			"doh|d"		=> \$OPTS{'doh'},
			"edns|e=s"	=> \$OPTS{'edns'},
			"file|f=s"	=> \$OPTS{'file'},
			"help|h"	=> \$OPTS{'h'},
			"json|j"	=> \$OPTS{'json'},
			"num|n=i"	=> \$OPTS{'num'},
			"resolver|r=s@"	=> \@{$OPTS{'resolvers'}},
			"public|p"	=> \$OPTS{'public'},
			"verbose|v+"	=> sub { $OPTS{'v'}++; },
		);

	if ($OPTS{'h'} || !$ok) {
		usage($ok);
		exit(!$ok);
		# NOTREACHED
	}

	if (!scalar(@ARGV)) {
		error("Give me something to look up.", EXIT_FAILURE);
		# NOTREACHED
	}

	$OPTS{'query'} = shift(@ARGV);
	if (scalar(@ARGV)) {
		@{$OPTS{'types'}} = map { uc($_) } @ARGV;
		%{$OPTS{'wanted'}} = map { uc($_) => 1; } @ARGV;

	} else {
		my @types = ( "A", "AAAA", "CNAME" );
		$OPTS{'types'} = \@types;
	}

	checkPTR();

	if ($OPTS{'1'} && $OPTS{'public'}) {
		error("'-1' cannot be combined with '-p'.", EXIT_FAILURE);
		# NOTREACHED
	}

	if ($OPTS{'file'} && $OPTS{'public'}) {
		error("'-f' and '-p' cannot be specified at the same time.", EXIT_FAILURE);
		# NOTREACHED
	}

	if ($OPTS{'doh'} && ($OPTS{'file'} || $OPTS{'public'})) {
		error("'-f' and '-p' cannot be combined with '-d'.", EXIT_FAILURE);
		# NOTREACHED
	}

	if ($OPTS{'country'} && !$OPTS{'doh'}) {
		error("'-c' can only be used in combination with '-d'.", EXIT_FAILURE);
		# NOTREACHED
	}

	if ($OPTS{'edns'}) {
	       	if (!$OPTS{'doh'}) {
			error("'-e' can only be used in combination with '-d'.", EXIT_FAILURE);
			# NOTREACHED
		}
		$EDNS_CLIENT_SUBNET = $OPTS{'edns'};
	}

	my $ulimit = `/bin/sh -c "ulimit -n"`;
	chomp($ulimit);
	if (($ulimit ne "unlimited") && ($ulimit > $CONCURRENCY)) {
		my $u = $ulimit / 2;
		if ($u > $CONCURRENCY) {
			$CONCURRENCY = $u;
		}
	}
}

sub parsePuddyFile() {
	verbose("Parsing input file $OPTS{'file'}...", 2);

	%RESOLVERS = ();
	my $n = 0;
	open(my $fh, "<", $OPTS{'file'}) or error("Unable to open $OPTS{'file'}: $!", EXIT_FAILURE);
	foreach my $line (<$fh>) {
		$line =~ s/#.*//;
		$line =~ s/^\s+//;
		$line =~ s/\s+$//;
		if ($line =~ m/^(\S+)(\s+(.*))?/) {
			my $ip = $1;
			my $comment = $OPTS{'file'};
			if ($3) {
				$comment = $3;
			}
			if (inet_pton(PF_INET, $ip)) {
				$RESOLVERS{"ipv4"}{$ip} = $comment;
			} elsif (inet_pton(PF_INET6, $ip)) {
				$RESOLVERS{"ipv6"}{$ip} = $comment;
			}
		}
	}
	close($fh);
}

sub parseEtcResolv() {
	my $resolv = "/etc/resolv.conf";
	verbose("Parsing $resolv...", 2);

	if (! -r $resolv) {
		return;
	}

	open(my $fh, "<", $resolv) or error("Unable to open $resolv: $!", EXIT_FAILURE);
	foreach my $line (<$fh>) {
		if ($line =~ m/^nameserver\s+(.*)/) {
			my $ip = $1;
			if ($ip =~ m/:/) {
				$RESOLVERS{"ipv6"}{$ip} = "/etc/resolv.conf";
			} else {
				$RESOLVERS{"ipv4"}{$ip} = "/etc/resolv.conf";
			}
		}
	}
	close($fh);
}

sub parseGivenResolvers() {
	my (@ipv4, @ipv6);

	foreach my $ip (@{$OPTS{'resolvers'}}) {
		if (inet_pton(PF_INET, $ip)) {
			push(@ipv4, $ip);
		} elsif (inet_pton(PF_INET6, $ip)) {
			push(@ipv6, $ip);
		} else {
			my $res = Net::DNS::Resolver->new;
			foreach my $type ( "A", "AAAA" ) {
				my $aref = \@ipv4;
				if ($type eq "AAAA") {
					$aref = \@ipv6;
				}

				my $query = $res->search($ip, $type);
				if (!$query) {
					error("Unable to resolve argument '$ip' to '-r'.", EXIT_FAILURE);
					# NOTREACHED
				}
				foreach my $rr ($query->answer) {
					if ($rr->type eq $type) {
						push(@{$aref}, $rr->address);
					}
				}
			}
		}
	}

	if ((scalar(@ipv4) > 0) && ($OPTS{'6'})) {
		error("You specified '-6', but the argument(s) to '-r' included (or resolved to) IPv4 addresses.");
		error("I'm going to ignore those.");
		@ipv4 = ();
	}

	if ((scalar(@ipv6) > 0) && ($OPTS{'4'})) {
		error("You specified '-4', but the argument(s) to '-r' included (or resolved to) IPv6 addresses.");
		error("I'm going to ignore those.");
		@ipv6 =();
	}

	foreach my $ip (@ipv4) {
		$RESOLVERS{"ipv4"}{$ip} = "command-line";
	}
	foreach my $ip (@ipv6) {
		$RESOLVERS{"ipv6"}{$ip} = "command-line";
	}
}


sub parsePublicResolvers() {
	verbose("Preparing list of resolvers from " . PUBLIC_URL . "...", 2);

	%RESOLVERS = ();

	my @cmd = ( "curl", "-s", PUBLIC_URL );
	open(my $out, "-|", @cmd) or error("Unable to open pipe to '".
						join(" ", @cmd) . "': $!", EXIT_FAILURE);
	foreach my $line (<$out>) {
		chomp($line);
		if (inet_pton(PF_INET, $line)) {
			$RESOLVERS{"ipv4"}{$line} = "";
		} elsif (inet_pton(PF_INET6, $line)) {
			$RESOLVERS{"ipv6"}{$line} = "";
		}
	}
	close($out);
}


sub ipv6Check() {
	verbose("Checking if we can even talk IPv6...", 2);

	my @ips = keys(%{$RESOLVERS{"ipv6"}});

	my $s = IO::Socket::INET6->new(
			PeerAddr => $ips[0],
			PeerPort => "53",
			Proto => "udp"
			);
	if (!$s) {
		error("Unable to open an IPv6 socket, ignoring all IPv6 resolvers.");
		$RESOLVERS{"ipv6"} = ();
	}
}


sub prepareListOfResolvers() {
	verbose("Preparing list of resolvers...");

	if ($OPTS{'file'}) {
		parsePuddyFile();
	} elsif ($OPTS{'public'}) {
		parsePublicResolvers();
	} else {
		parseEtcResolv();
	}

	if ($OPTS{'resolvers'}) {
		parseGivenResolvers();
	}

	if ($OPTS{'4'}) {
		$RESOLVERS{"ipv6"} = ();
	} elsif ($OPTS{'6'}) {
		$RESOLVERS{"ipv4"} = ();
	}

	if (!$OPTS{'doh'}) {
		ipv6Check();
	} else {
		# Ok, we're cheating a bit here.  We don't know
		# (or care) which ones are IPv4, so let's just
		# pretend they all are.
		$RESOLVERS{"ipv6"} = ();
		$RESOLVERS{"ipv4"} = \%DOH;
	}


	if ($OPTS{'num'}) {
		my %resolvers;

		my @ipv4 = shuffle(keys(%{$RESOLVERS{"ipv4"}}));
		my @ipv6 = shuffle(keys(%{$RESOLVERS{"ipv6"}}));

		if ($OPTS{'num'} > (scalar(@ipv4) + scalar(@ipv6))) {
			error("List of resolvers is smaller than $OPTS{'num'}, so using all instead.");
			return;
		}

		my $numv4 = int(rand($OPTS{'num'}));

		while ($numv4 > scalar(@ipv4)) {
			$numv4--;
		}

		my $numv6 = $OPTS{'num'} - $numv4;
		while ($numv6 > scalar(@ipv6)) {
			$numv6--;
			$numv4++;
		}

		foreach my $n (0 .. ($numv4 - 1)) {
			my $ip = $ipv4[$n];
			$resolvers{"ipv4"}{$ip} = $RESOLVERS{"ipv4"}{$ip};
		}

		foreach my $n (0 .. ($numv6 - 1)) {
			my $ip = $ipv6[$n];
			$resolvers{"ipv6"}{$ip} = $RESOLVERS{"ipv6"}{$ip};
		}

		%RESOLVERS = %resolvers;
	}
}


sub printResults() {

	if ($OPTS{'json'}) {
		my $json = JSON->new;
		print $json->pretty->encode(\%RESULTS);
	} else {
		printResultsPlain();
	}
}

sub printResultsPlain() {
	my @ips = keys(%{$RESULTS{"results"}});
	my (@ipv4, @ipv6);

	if ($OPTS{'doh'}) {
		# Again overloading the "ipv4" array for DoH.
		@ipv4 = sort(@ips);
	} else {
		foreach my $ip (@ips) {
			if (inet_pton(PF_INET, $ip)) {
				push(@ipv4, $ip);
			} elsif (inet_pton(PF_INET6, $ip)) {
				push(@ipv6, $ip);
			}
		}

		@ipv4 = sortIPv4(@ipv4);
		@ipv6 = sort(@ipv6);
	}

	foreach my $ip (@ipv6, @ipv4) {
		if (!$RESULTS{"results"}{$ip}) {
			next;
		}
		my %oneResult = %{$RESULTS{"results"}{$ip}};
		print $ip;
		if ($oneResult{"comment"}) {
			print " (" . $oneResult{"comment"} . ")";
		}

		# Some resolvers always return an ECS.
		if ($EDNS_CLIENT_SUBNET || $oneResult{"edns_client_subnet"}) {
			print " (ECS ";
		}
		if ($EDNS_CLIENT_SUBNET) {
			print "sent: $EDNS_CLIENT_SUBNET; ";
			if (!$oneResult{"edns_client_subnet"}) {
				print "ignored by server";
			}
		}
		if ($oneResult{"edns_client_subnet"}) {
			if ($EDNS_CLIENT_SUBNET) {
				print "ECS ";
			}
			print "returned: " . $oneResult{"edns_client_subnet"};
		}
		if ($EDNS_CLIENT_SUBNET || $oneResult{"edns_client_subnet"}) {
			print ")";
		}
		print "\n";

		my $n = 0;
		foreach my $k (sort(keys(%oneResult))) {
			if (($k eq "comment") || ($k eq "edns_client_subnet")) {
				$n = 1;
				next;
			}
			if ($oneResult{$k}{"status"} && $oneResult{$k}{"status"} ne "NOERROR") {
				$n = 1;
				print "\t$k: " . $oneResult{$k}{"status"} . "\n";
			} elsif (!($oneResult{$k}{"status"} && $oneResult{$k}{"rrs"}) && $OPTS{'wanted'}{$k}) {
					# even if we didn't find data
					# we still got a result, so set $n
					$n = 1;
					print "\t$k: [NO RECORD FOUND]\n";
			}

			my $sortFunc;
			if ($k eq "A") {
				$sortFunc = sub {
					my %a = %{$a};
					my %b = %{$b};
					my $v1 = $a{"value"};
					my $v2 = $b{"value"};
					if ($v1 eq $v2) {
						return 0;
					}
					my $i1 = new Net::IP ($v1);
					my $i2 = new Net::IP ($v2);
					if ($i1->bincomp('lt', $i2)) {
						return -1;
					} else {
						return 1;
					}
				};
			} else {
				$sortFunc = sub { my %a = %{$a}; my %b = %{$b};
						return $a{"value"} cmp $b{"value"};
				};
			}

			if ($oneResult{$k}{"rrs"}) {
				my @data = @{$oneResult{$k}{"rrs"}};
				foreach my $ref (sort $sortFunc @{$oneResult{$k}{"rrs"}}) {
					$n++;
					my %data= %{$ref};
					print "\t$k (" . $data{"ttl"} ."): " . $data{"value"} . "\n";
				}
			}
		}

		if (!$n) {
			print "\tNO RESULTS\n";
		}
	}
}


sub queryDOH($$$) {
	my ($url, $query, $type) = @_;
	my %dohResults;

	my $provider = $DOH{$url};

	verbose("Querying $provider for '$query' ($type) via DoH...", 4);
	$url .= "name=" . uri_escape($query) . "&type=" . uri_escape($type);

	if ( ($OPTS{'country'} || $OPTS{'edns'}) && $EDNS_CLIENT_SUBNET) {
		$url .= "&edns_client_subnet=$EDNS_CLIENT_SUBNET";
	}

	verbose("Full URL: $url", 5);

	# We call out to curl(1) because it turns out
	# that the various ways to fetch https resources
	# in Perl across platforms are less uniform or
	# predictable with regards to the presence of
	# a proper CA bundle and support for modern ciphers
	# (Google DNS, for example, requires TLS >= 1.2 and
	# only supports ECDHE) than curl(1).
	my @cmd = ( "curl", "-s",
			"-H", "Accept: application/dns-json",
			"$url");

	open(my $out, "-|", @cmd) or error("Unable to open pipe from '".
						join(" ", @cmd) . "': $!", EXIT_FAILURE);
	my $json = JSON->new->allow_nonref;
	my $data = <$out>;
	my $result;
	eval {
		$result = $json->decode($data);
	};
	if ($@) {
		# E.g., Google DNS returns a 500 error on invalid query type.
		$dohResults{"status"} = "Unable to query '$url'.";
		return;

	};
	close($out);

	if (!$result) {
		error("Unable to parse json from '$url'.", EXIT_FAILURE);
		# NOTREACHED
	}

	my @answers;
	if ($result->{"Answer"}) {
		@answers = @{$result->{"Answer"}};
		if (!scalar(@answers)) {
			return;
		}
	}

	foreach my $href (@answers) {
		my %a = %{$href};
		my $t = $a{type};
		my $foundType = typebyval($t);
		if (!$foundType) {
			$dohResults{"status"} = "Unknown RR type '$t'.";
			next;
		} else {
			my $status = $result->{"Status"};
			$dohResults{"status"} = rcodebyval($status);

			if ($result->{"edns_client_subnet"}) {
				$dohResults{"edns_client_subnet"} = $result->{"edns_client_subnet"};
			}
		}

		if ($foundType ne $type) {
			# e.g., an A lookup against a CNAME
			next;
		}

		my %tuple = (
			"value" => $a{"data"},
			"ttl" => $a{"TTL"},
		);
		if ($dohResults{"rrs"}) {
			push(@{$dohResults{"rrs"}}, \%tuple);
		} else {
			@{$dohResults{"rrs"}} = ( \%tuple );
		}
	}
	return \%dohResults;
}


sub queryOneResolver($$$) {
	my ($r, $org, $query) = @_;

	my $msg = "Querying $r ";
	if ($org) {
		$msg .= "($org)";
		$RESULTS{"results"}{$r}{"comment"} = $org;
	}
	$msg .= "...";

	verbose($msg, 2);
	my %resolverResults;

	foreach my $type (@{$OPTS{'types'}}) {
		$resolverResults{$type} = queryOneResolverForRR($r, $query, $type);
		# We're cheating a bit here: ECS is returned for each type
		# but we assume that the same ECS will be used for each.
		# This isn't necessarily but at least apparently so,
		# so for presentation purposes, this makes things a bit easier.
		if ($resolverResults{$type}{"edns_client_subnet"}) {
			$resolverResults{"edns_client_subnet"} = $resolverResults{$type}{"edns_client_subnet"};
			delete($resolverResults{$type}{"edns_client_subnet"});
		}
	}

	return \%resolverResults;
}

sub queryOneResolverForRR($$$) {
	my ($r, $query, $type) = @_;

	verbose("Looking up RR $type...", 3);

	my %result;

	if ($OPTS{'doh'}) {
		return queryDOH($r, $query, $type);
	}

	my ($res, $q);
	my $timeout = 1;

	eval {
		local $SIG{ALRM} = sub { die "alarm\n"; };
		alarm($timeout);
		$res = Net::DNS::Resolver->new(
			nameservers => [$r],
			udp_timeout => 1,
			tcp_timeout => 1,
			debug => 0,
		);
		$q = $res->send($query, $type);
		alarm(0);
	};
	if ($@) {
		$result{"status"} = "timed out";
		return \%result;
	}

	$result{"status"} = $res->errorstring;
	if ($q) {
		foreach my $rr ($q->answer) {
			if ($rr->type ne $type) {
				# e.g., an A lookup against a CNAME
				next;
			}
			my %tuple = (
				"value" => $rr->rdstring,
				"ttl" => $rr->ttl,
				);
			if ($result{"rrs"}) {
				push(@{$result{"rrs"}}, \%tuple);
			} else {
				@{$result{"rrs"}} = ( \%tuple );
			}
		}
	}
	return \%result;
}

sub queryResolvers() {
	my $n = scalar(keys(%{$RESOLVERS{"ipv4"}})) + scalar(keys(%{$RESOLVERS{"ipv6"}}));
	verbose("Querying $n resolvers...");

	my %seen;
	my @classes = ( "ipv6", "ipv4" );

	my $query = $OPTS{'query'};

	$RESULTS{"query"} = $query;
	$RESULTS{"type"} = \@{$OPTS{'types'}};

	my $pm = Parallel::ForkManager->new($CONCURRENCY);
	$pm->run_on_finish(sub {
				my (undef, undef, undef, undef, undef, $ref) = @_;
				my @values = @{$ref};
				my $key = $values[0];
				if ($OPTS{'doh'}) {
					$key = $DOH{$key};
				}
				$RESULTS{"results"}{$key} = $values[1];
				if ($OPTS{'doh'}) {
					$RESULTS{"results"}{$key}{"comment"} = $values[0];
				}
			});

	foreach my $c (@classes) {
LOOP:
		foreach my $r (keys(%{$RESOLVERS{$c}})) {
			my $org = $RESOLVERS{$c}{$r};

			if ($OPTS{'1'} && $seen{$org} && $org ne "command-line") {
				verbose("Skipping $r ($org already queried)...", 2);
				next;
			}

			$seen{$org} = 1;

			$pm->start() and next LOOP;
			my $hr = queryOneResolver($r, $org, $query);
			my %oneResult = %{$hr};
			if ($OPTS{'doh'}) {
				$oneResult{"comment"} = $query;
			}
			my @values = ($r, \%oneResult);

			$pm->finish(0, \@values);
		}
		$pm->wait_all_children();
	}
}


sub sortIPv4(@) {

	my (@ipv4) = @_;

	# map address to 32bit number representation,
	# sort keys of numbers, then remove the 32bit number representation again
	my %numeric = map { inet_pton(PF_INET, $_) => $_ } @ipv4;
	@ipv4 = ();
	foreach my $ip (sort(keys(%numeric))) {
		push(@ipv4, $numeric{$ip});
	}
	return @ipv4;
}

sub usage($) {
	my ($err) = @_;

	my $FH = $err ? \*STDERR : \*STDOUT;

	print $FH <<EOH
Usage: $PROGNAME [-146Vdhjpv] [-c country] [-e cidr] [-f file] [-n num] [-r resolver] query [type ...]
	-1           only use one resolver per organization
	-4           only query IPv4 resolvers
	-6           only query IPv6 resolvers
	-V           print version number and exit
	-c country   use edns_client_subnet to fake traffic from this country
	-d           use DNS over HTTPS resolvers
	-e cidr      use this cidr as edns_client_subnet
	-f file      read list of resolvers from file
	-h           print this help and exit
	-j           print output in json format
	-n num       query at most this many resolvers
	-p           query all known public resolvers
	-r resolver  add this resolver to the list to query
	-v           be verbose
EOH
	;
}

sub verbose($;$) {
	my ($msg, $level) = @_;
	my $char = "=";

	return unless $OPTS{'v'};

	$char .= "=" x ($level ? ($level - 1) : 0 );

	if (!$level || ($level <= $OPTS{'v'})) {
		print STDERR "$char> $msg\n";
	}
}


###
### Main
###

init();
prepareListOfResolvers();
if ($OPTS{'country'}) {
	getCountryNetblocks();
}
queryResolvers();
printResults();

exit($RETVAL);
