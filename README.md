# puddy - because sometimes you gotta ask the magic 8.8.8.8 ball

`puddy(1)` is a tool to successively query (public)
DNS servers and present to you their results.

Please see the [manual
page](https://github.com/jschauma/puddy/blob/master/doc/puddy.1.txt)
for details.

## Requirements

`puddy(1)` is old-school.  You'll need to have Perl
and the following modules installed:

* IO::Socket::INET6
* JSON
* Net::DNS
* Net::IP
* Net::Netmask

## Installation

You can install `puddy(1)` by running `make install`.
The Makefile defaults to '/usr/local' as the prefix,
but you can change that, if you like:

```
$ make PREFIX=~ install
```

---
```
NAME
     puddy -- public DNS data yielder

SYNOPSIS
     puddy [-146Vdhjpv] [-c country] [-f file] [-n num] [-r resolver] query
	   [type ...]

DESCRIPTION
     The puddy tool allows you to query a number of different resolvers to
     compare whether results are uniform across the internet.

OPTIONS
     The following options are supported by puddy:

     -1		  Only use a single resolver from one and the same organiza-
		  tion.	 This option cannot be combined with the -p flag.  See
		  Section PUBLIC RESOLVERS for details.

     -4		  Only query IPv4 resolvers.

     -6		  Only query IPv6 resolvers.

     -V		  Print version number and exit.

     -c country	  Try to use the EDNS Client Subnet (ECS) extension to elicit
		  a response from the DNS server as if the client was located
		  in the given country.

		  The argument country can be a country code or the name of a
		  country.

		  See Section COUNTRY IMITATION for details.

     -d		  Use DNS-over-HTTPS.  This option only works with a subset of
		  the known public resolvers and thus conflicts with e.g., the
		  -f and -p flags.

     -f file	  Read the list of resolvers to query from this file.  This
		  option conflicts with the -p flag.  See Section FILES for
		  details.

     -h		  Display help and exit.

     -j		  Print output in json format.

     -n num	  Only query at most this many resolvers.

     -p		  Query all known public DNS resolvers.	 This option conflicts
		  with the -f flag.  See Section PUBLIC RESOLVERS for details.

     -r resolver  Add the given resolver to the list of resolvers to query.
		  Can be specified multiple times.

     -v		  Be verbose.  Can be specified multiple times.

DETAILS
     Sometimes it can be useful to check whether a given hostname or record
     resolves to the same value in different places on the internet, so you go
     and ask the magic 8.8.8.8 ball.  But perhaps other resolvers elsewhere
     have different results?  Manually querying multiple resolvers is labor-
     some, do instead puddy saves you some typing by performing these lookups
     in succession for you.

     By default, puddy will query resolvers for A, AAAA, and CNAME records,
     similar to the host(1) command.

PUBLIC RESOLVERS
     If the -p flag is given, puddy will retrieve the list of known public DNS
     resolvers from https://public-dns.info/nameservers.txt and query each
     one.

     Otherwise, if the -f flag is given, puddy will read the list of resolvers
     to query from the specified file.

     Many organizations offer public DNS services on multiple IP addresses; if
     the list of resolvers to use contains multiple IP address for the same
     organization, and you only want one of those servers, specify the -1
     (numeric one) flag.  puddy will then pick only of the IPs for each orga-
     nization from the input set.  Note: If an organization's resolvers are
     reachable via both IPv4 and IPv6 addresses, then puddy will prefer the
     IPv6 address.

     If the -d flag is specified, puddy will query a short list of hardcoded
     public resolvers known to support DNS-over-HTTPS with results returned in
     JSON format:
	   Cloudflare
	   DNS.SB
	   Google
	   Netweaver
	   Quad9
	   SecureDNS.eu
	   doh.li

     If neither the -d, -f, or -p flag is specified, puddy will only query a
     short list of hardocded, popular public resolvers, which consists of:
	   Cloudflare
	   Google
	   Hurricane Electric
	   OpenDNS
	   Quad9

     In addition, puddy will also query the resolvers found in
     /etc/resolv.conf.

     Finally, if the -n flag is specified, then at most this many resolvers
     will be queried; the list is randomized before the selection of resolvers
     to query is made.

FILES
     puddy may read a list of public resolvers to query from a file provided
     via the -f flag.  Each line in the file is expected to consist of an IP
     address and an optional comment or identifier.  Leading and trailing
     whitespace as well as empty lines and anything following the '#' charac-
     ter are ignored.

     An example puddy.resolvers file might look like so:

	   # puddy.resolvers file
	   216.146.35.35 Dyn
	   2001:470:1f10:c6::2001 OpenNIC
	   10.0.0.1 My Private Resolver # not /etc/resolv.conf!

     puddy may have come with a list of public resolvers in
     /usr/local/share/puddy.resolvers.

COUNTRY IMITATION
     Sometimes it is useful to be able to see if different resolvers might
     give different responses based on where the client is located.  puddy
     supports the -c country option to attempt to elicit a response from the
     DNS server as if the client was in the given location.  This is done
     through the use of the EDNS Client Subnet extension (ECS, see RFC7871).

     Note: at this time, puddy only supports this option when performing
     queries using DNS over HTTPS (i.e., in combination with the -d option).

     When specified, puddy will try to look up a suitable netblock for the
     given country via the site http://services.ce3c.be/ciprg/, then set the
     ECS option.

     If you wish to disable the use of the ECS extension altogether, then you
     can pass 'none' as an argument to the -c flag, yielding a netblock of
     0.0.0.0/0.

     Note: not all DoH providers honor this option, but puddy has no way of
     telling the difference.  In addition, even for those resolvers that do
     support it, there is no guarantee that the result returned does in fact
     reflect what would be returned to a client query actually originating
     from that netblock.

EXAMPLES
     The following examples illustrate common usage of this tool.

     To look up the IP addresses for www.yahoo.com on the short list of public
     resolvers, limiting to one query per organization:

	   $ puddy -1 www.yahoo.com
	   2001:470:20::2 (Hurricane Electric)
		   A (20): 72.30.35.10
		   A (20): 72.30.35.9
		   AAAA (56): 2001:4998:58:1836::11
		   AAAA (56): 2001:4998:58:1836::10
		   CNAME (1759): atsv2-fp-shed.wg1.b.yahoo.com.
	   2001:4860:4860::8888 (Google)
		   A (15): 98.138.219.231
		   A (15): 72.30.35.9
		   A (15): 72.30.35.10
		   A (15): 98.138.219.232
		   AAAA (45): 2001:4998:44:41d::4
		   AAAA (45): 2001:4998:44:41d::3
		   AAAA (45): 2001:4998:58:1836::11
		   AAAA (45): 2001:4998:58:1836::10
		   CNAME (77): atsv2-fp-shed.wg1.b.yahoo.com.
	   2606:4700:4700::1001 (Cloudflare)
		   A (38): 72.30.35.10
		   A (38): 72.30.35.9
		   AAAA (33): 2001:4998:58:1836::10
		   AAAA (33): 2001:4998:58:1836::11
		   CNAME (15): atsv2-fp-shed.wg1.b.yahoo.com.
	   2620:0:ccc::2 (OpenDNS)
		   A (18): 72.30.35.9
		   A (18): 72.30.35.10
		   AAAA (45): 2001:4998:58:1836::10
		   AAAA (45): 2001:4998:58:1836::11
		   CNAME (1531): atsv2-fp-shed.wg1.b.yahoo.com.
	   2620:fe::fe (Quad9)
		   A (15): 72.30.35.9
		   A (15): 72.30.35.10
		   AAAA (56): 2001:4998:58:1836::11
		   AAAA (56): 2001:4998:58:1836::10
		   CNAME (772): atsv2-fp-shed.wg1.b.yahoo.com.
	   172.131.44.74 (/etc/resolv.conf)
		   A (46): 74.6.143.8
		   AAAA (51): 2001:4998:58:207::1000
		   CNAME (1800): atsv2-fp-shed.wg1.b.yahoo.com.

     To only query at most 2 IPv6 resolvers from the public list of public
     resolvers for NS records, one of which does not respond in time:

	   $ puddy -6 -n 2 -p netmeister.org NS
	   2610:a1:1019::31
		   NS: timed out
	   2610:a1:1019::32
		   NS (10799): ns-143-b.gandi.net.
		   NS (10799): ns-179-c.gandi.net.
		   NS (10799): ns-181-a.gandi.net.

     To query 3 DoH providers:

	   $ puddy -n 3 -d  _443._tcp.mta-sts.netmeister.org TLSA
	   DNS.SB (https://doh.dns.sb/dns-query?)
		   TLSA (3600): 3 1 1 905254acd0785b76b76b42da2c419d065b2442427883f133c9305f2010ae6397
	   Google (https://dns.google/resolve?)
		   TLSA (3599): 3 1 1 905254acd0785b76b76b42da2c419d065b2442427883f133c9305f2010ae6397
	   Quad9 (https://9.9.9.9:5053/dns-query?)
		   TLSA (3600): 3 1 1 905254acd0785b76b76b42da2c419d065b2442427883f133c9305f2010ae6397

     To get DoH results with an EDNS Client Subnet set to a netblock from
     China:

	   $ puddy -d -c cn www.google.cn
	   Cloudflare (https://cloudflare-dns.com/dns-query?)
		   A (105): 172.217.11.3
		   AAAA (55): 2607:f8b0:4006:812::2003
	   DNS.SB (https://doh.dns.sb/dns-query?) (ECS 45.126.116.0/22)
		   A (300): 203.208.39.207
		   A (300): 203.208.39.216
		   A (300): 203.208.39.223
		   A (300): 203.208.39.215
	   Google (https://dns.google/resolve?) (ECS 45.126.116.0/22)
		   A (299): 203.208.39.223
		   A (299): 203.208.39.207
		   A (299): 203.208.39.215
		   A (299): 203.208.39.216
	   Netweaver (https://doh.netweaver.uk/dns-query?)
		   A (300): 172.217.169.3
		   AAAA (300): 2a00:1450:4009:807::2003
	   Quad9 (https://9.9.9.9:5053/dns-query?)
		   A (300): 172.217.7.3
		   AAAA (300): 2607:f8b0:4006:801::2003
	   SecureDNS.eu (https://doh.securedns.eu/dns-query?) (ECS 45.126.116.0/0)
		   A (900): 172.217.22.99
		   AAAA (900): 2a00:1450:4001:81d::2003
	   doh.li (https://doh.li/dns-query?) (ECS 45.126.116.0/22)
		   A (300): 203.208.39.216
		   A (300): 203.208.39.215
		   A (300): 203.208.39.207
		   A (300): 203.208.39.223

     To get the results from the resolvers specified in the file
     /usr/local/share/puddy.resolvers and generate output in json format:

	   $ puddy -j -f /usr/local/share/puddy.resolvers whocybered.me txt
	   {
	      "results" : {
		 "209.244.0.3" : {
		    "TXT" : {
		       "status" : "NOERROR",
		       "rrs" : [
			  {
			     "value" : "\"Attribution is hard. Cyber doubly so. When in doubt, APT.\"",
			     "ttl" : 10795
			  }
		       ]
		    },
		    "comment" : "/tmp/f"
		 },
		 "2620:74:1b::1:1" : {
		    "TXT" : {
		       "status" : "NOERROR",
		       "rrs" : [
			  {
			     "ttl" : 10794,
			     "value" : "\"Attribution is hard. Cyber doubly so. When in doubt, APT.\""
			  }
		       ]
		    },
		    "comment" : "/tmp/f"
		 }
	      },
	      "query" : "whocybered.me"
	   }

EXIT STATUS
     The puddy utility exits 0 on success, and >0 if an error occurs.

NOTES
     Feels like an Arby's night.

SEE ALSO
     dig(1), host(1), nslookup(1)

     RFC7871

HISTORY
     puddy was originally written by Jan Schaumann <jschauma@netmeister.org> in
     September 2019.

BUGS
     Please file bugs and feature requests by emailing the author.
```
