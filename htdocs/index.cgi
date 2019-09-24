#! /usr/pkg/bin/perl -Tw
#
# Originally written by Jan Schaumann
# <jschauma@netmeister.org> in September 2019.
#
# This CGI provides a web frontend to puddy(1):
# https://github.com/jschauma/puddy

use strict;
use CGI qw(:standard);

print "Content-Type: text/html; charset=utf-8\n\n";

###
### Globals
###

my $PUDDY = "/usr/local/bin/puddy";
my $RESOLVERS = "/htdocs/netmeister.org/puddy/resolvers";
my @CMD = ( $PUDDY, "-1" );

# per http://services.ce3c.be/ciprg/
my @COUNTRIES = (
	"AFGHANISTAN",
	"ALAND ISLANDS",
	"ALBANIA",
	"ALGERIA",
	"AMERICAN SAMOA",
	"ANDORRA",
	"ANGOLA",
	"ANGUILLA",
	"ANTARCTICA",
	"ANTIGUA AND BARBUDA",
	"ARGENTINA",
	"ARMENIA",
	"ARUBA",
	"AUSTRALIA",
	"AUSTRIA",
	"AZERBAIJAN",
	"BAHAMAS",
	"BAHRAIN",
	"BANGLADESH",
	"BARBADOS",
	"BELARUS",
	"BELGIUM",
	"BELIZE",
	"BENIN",
	"BERMUDA",
	"BHUTAN",
	"BOLIVIA",
	"BONAIRE; SINT EUSTATIUS; SABA",
	"BOSNIA AND HERZEGOWINA",
	"BOTSWANA",
	"BRAZIL",
	"BRITISH INDIAN+OCEAN TERRITORY",
	"BRUNEI DARUSSALAM",
	"BULGARIA",
	"BURKINA FASO",
	"BURUNDI",
	"CAMBODIA",
	"CAMEROON",
	"CANADA",
	"CAPE VERDE",
	"CAYMAN ISLANDS",
	"CENTRAL AFRICAN REPUBLIC",
	"CHAD",
	"CHILE",
	"CHINA",
	"COLOMBIA",
	"COMOROS",
	"CONGO",
	"CONGO THE DEMOCRATIC REPUBLIC OF THE",
	"COOK ISLANDS",
	"COSTA RICA",
	"COTE D'IVOIRE",
	"CROATIA (LOCAL NAME: HRVATSKA)",
	"CUBA",
	"CURACAO",
	"CYPRUS",
	"CZECH REPUBLIC",
	"DENMARK",
	"DJIBOUTI",
	"DOMINICA",
	"DOMINICAN REPUBLIC",
	"ECUADOR",
	"EGYPT",
	"EL SALVADOR",
	"EQUATORIAL GUINEA",
	"ERITREA",
	"ESTONIA",
	"ETHIOPIA",
	"EUROPEAN UNION",
	"FALKLAND ISLANDS (MALVINAS)",
	"FAROE ISLANDS",
	"FIJI",
	"FINLAND",
	"FRANCE",
	"FRENCH GUIANA",
	"FRENCH POLYNESIA",
	"GABON",
	"GAMBIA",
	"GEORGIA",
	"GERMANY",
	"GHANA",
	"GIBRALTAR",
	"GREECE",
	"GREENLAND",
	"GRENADA",
	"GUADELOUPE",
	"GUAM",
	"GUATEMALA",
	"GUERNSEY",
	"GUINEA",
	"GUINEA-BISSAU",
	"GUYANA",
	"HAITI",
	"HOLY SEE (VATICAN CITY STATE)",
	"HONDURAS",
	"HONG KONG",
	"HUNGARY",
	"ICELAND",
	"INDIA",
	"INDONESIA",
	"IRAN (ISLAMIC REPUBLIC OF)",
	"IRAQ",
	"IRELAND",
	"ISLE OF MAN",
	"ISRAEL",
	"ITALY",
	"JAMAICA",
	"JAPAN",
	"JERSEY",
	"JORDAN",
	"KAZAKHSTAN",
	"KENYA",
	"KIRIBATI",
	"KOREA DEMOCRATIC PEOPLE's REPUBLIC OF",
	"KOREA REPUBLIC OF",
	"KUWAIT",
	"KYRGYZSTAN",
	"LAO PEOPLE'S DEMOCRATIC REPUBLIC",
	"LATVIA",
	"LEBANON",
	"LESOTHO",
	"LIBERIA",
	"LIBYAN ARAB JAMAHIRIYA",
	"LIECHTENSTEIN",
	"LITHUANIA",
	"LUXEMBOURG",
	"MACAU",
	"MACEDONIA",
	"MADAGASCAR",
	"MALAWI",
	"MALAYSIA",
	"MALDIVES",
	"MALI",
	"MALTA",
	"MARSHALL ISLANDS",
	"MARTINIQUE",
	"MAURITANIA",
	"MAURITIUS",
	"MAYOTTE",
	"MEXICO",
	"MICRONESIA FEDERATED STATES OF",
	"MOLDOVA REPUBLIC OF",
	"MONACO",
	"MONGOLIA",
	"MONTENEGRO",
	"MONTSERRAT",
	"MOROCCO",
	"MOZAMBIQUE",
	"MYANMAR",
	"NAMIBIA",
	"NAURU",
	"NEPAL",
	"NETHERLANDS",
	"NEW CALEDONIA",
	"NEW ZEALAND",
	"NICARAGUA",
	"NIGER",
	"NIGERIA",
	"NIUE",
	"NON-SPEC ASIA PAS LOCATION",
	"NORFOLK ISLAND",
	"NORTHERN MARIANA ISLANDS",
	"NORWAY",
	"OMAN",
	"PAKISTAN",
	"PALAU",
	"PALESTINIAN TERRITORY OCCUPIED",
	"PANAMA",
	"PAPUA NEW GUINEA",
	"PARAGUAY",
	"PERU",
	"PHILIPPINES",
	"POLAND",
	"PORTUGAL",
	"PUERTO RICO",
	"QATAR",
	"RESERVED",
	"REUNION",
	"ROMANIA",
	"RUSSIAN FEDERATION",
	"RWANDA",
	"SAINT KITTS AND NEVIS",
	"SAINT LUCIA",
	"SAINT MARTIN",
	"SAINT VINCENT AND THE GRENADINES",
	"SAMOA",
	"SAN MARINO",
	"SAO TOME AND PRINCIPE",
	"SAUDI ARABIA",
	"SENEGAL",
	"SERBIA",
	"SEYCHELLES",
	"SIERRA LEONE",
	"SINGAPORE",
	"SINT MAARTEN",
	"SLOVAKIA (SLOVAK REPUBLIC)",
	"SLOVENIA",
	"SOLOMON ISLANDS",
	"SOMALIA",
	"SOUTH AFRICA",
	"SOUTH SUDAN",
	"SPAIN",
	"SRI LANKA",
	"ST. PIERRE AND MIQUELON",
	"SUDAN",
	"SURINAME",
	"SWAZILAND",
	"SWEDEN",
	"SWITZERLAND",
	"SYRIAN ARAB REPUBLIC",
	"TAIWAN; REPUBLIC OF CHINA (ROC)",
	"TAJIKISTAN",
	"TANZANIA UNITED REPUBLIC OF",
	"THAILAND",
	"TIMOR-LESTE",
	"TOGO",
	"TOKELAU",
	"TONGA",
	"TRINIDAD AND TOBAGO",
	"TUNISIA",
	"TURKEY",
	"TURKMENISTAN",
	"TURKS AND CAICOS ISLANDS",
	"TUVALU",
	"UGANDA",
	"UKRAINE",
	"UNITED ARAB EMIRATES",
	"UNITED KINGDOM",
	"UNITED STATES",
	"URUGUAY",
	"UZBEKISTAN",
	"VANUATU",
	"VENEZUELA",
	"VIET NAM",
	"VIRGIN ISLANDS (BRITISH)",
	"VIRGIN ISLANDS (U.S.)",
	"WALLIS AND FUTUNA ISLANDS",
	"YEMEN",
	"ZAMBIA",
	"ZIMBABWE",

);

$ENV{'PATH'} = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/pkg/bin";

my $CGI = new CGI;

###
### Functions
###

sub printError($$) {
	my ($err, $format) = @_;

	if ($format eq "json") {
		print "{ \"Error\" : \"$err\" }";
	} else {
		print "<b><font color=\"red\">$err</font></b>\n";
	}
}

sub runPuddy() {

	my $error = 0;
	my $format = $CGI->param('format');
	if ($format eq "json") {
		push(@CMD, "-j");
	}

	if ($CGI->param('lookup') eq "doh") {
		push(@CMD, "-d");
		my $c = $CGI->param('country');
		if ($c && ($c =~ m/^([a-z;:()']+)$/i)) {
			push(@CMD, "-c", $1);
		}
	} else {
		push(@CMD, "-f", $RESOLVERS);
	}

	my $name = $CGI->param('name');
	if (!$name) {
		printError("Missing name", $format);
		$error = 1;
	}

	if ($name =~ m/^([a-z0-9.-]+)$/i) {
		$name = $1;
	} else {
		printError("Invalid name: $name", $format);
		$error = 1;
	}
	push(@CMD, $name);

	my @types;
	if ($CGI->param('type')) {
		foreach my $t (split(/,|\s/, $CGI->param('type'))) {
			if ($t =~ m/^([a-z]+)/i) {
				push(@types, $1);
			} else {
				printError("Invalid type: $t", $format);
				$error = 1;
			}
		}
		if (scalar(@types)) {
			push(@CMD, @types);
		}
	} else {
		push(@types, "A", "AAAA", "CNAME");
	}

	if (!$error) {
		if ($format ne "json") {
			print "<b>Name:</b> $name<br>\n";
			print "<b>Type:</b> " . join(", ", @types) . "<br>\n";
			print "<b>Lookup type:</b> " . $CGI->param('lookup') . "<br>\n";
			if ($CGI->param('country')) {
				print "<b>ECS Country Netblock:</b> " . $CGI->param('country') ."<br>\n";
			}
			print "<div id=\"waiting\">Query sent, sit tight...<br>\n";
			print "<img src=\"puddy.jpg\" id=\"puddy-sitting\" alt=\"David Puddy sitting on the couch\" title=\"Yeah, that's right.\"></div>\n";
			print "\n\n<blockquote><tt><pre>\n";
		}
		system(@CMD);
		if ($format ne "json") {
			print "</pre></tt></blockquote>\n";
		}
	}
}

sub printHead() {
	print <<EOD
<HTML>
  <HEAD>
    <TITLE>puddy -- because sometimes you gotta ask the magic 8.8.8.8 ball</TITLE>
    <link rel="stylesheet" type="text/css" href="puddy.css">
    <script type="text/javascript">
	window.onload = function() {
		document.getElementById('waiting').style.display='none';
	}
    </script>
  </HEAD>
  <BODY>
  <h2>Compare public DNS resolver results</h2>
  <hr>
EOD
;
}

sub printInstructions() {
	print <<EOD
  <p>
    <img src="puddy.gif" align="right" alt="David Puddy pointint to his 8-ball jacket" title="All signs point to yes.">
Sometimes it can be useful to check whether a given
hostname or record resolves to the same value in
different places on the internet, so you go and ask
the magic 8.8.8.8 ball.  But perhaps other resolvers
elsewhere have different results?  Manually querying
multiple resolvers is bogus, man, so this service
does the work for you.
  </p>
  <p>
Enter a name and record type to look up and <a
href="https://github.com/jschauma/puddy">puddy</a>
will take care of the rest.
  </p>
  <p>
By default, this service will query a bunch of public
DNS resolvers via regular UDP port 53 DNS queries;
if you choose <a
href="https://en.wikipedia.org/wiki/DNS_over_HTTPS">DNS-over-HTTPS</a>,
several public DoH providers will be asked instead.
  </p>
  <p>
If you select an ECS Country Subnet, we'll try to set
the <a
href="https://en.wikipedia.org/wiki/EDNS_Client_Subnet">EDNS
Client Subnet</a> parameter to a subnet allocated to
that country in the hopes that the DoH providers will
honor it and return results for that given ECS.
  </p>
  <p>
Finally, if HTML isn't your thing, you can also
request JSON output, which then lends itself to
querying this service from the command-line via e.g.,
<blockquote><tt>curl "https://www.netmeister.org/puddy/index.cgi?name=wikipedia.org&type=A&format=json&lookup=doh&country=CHINA" | python -m json.tool</tt></blockquote>
  </p>
  <hr width="75%">
EOD
;
}

sub printFoot() {
	print <<EOD
  <hr>
  [Made by <a href="https://twitter.com/jschauma">\@jschauma</a>&nbsp;|&nbsp;[<a href="index.cgi">about</a>]&nbsp;|&nbsp;[<a href="/blog/">Other Signs of Triviality</a>]
  </BODY>
</HTML>
EOD
;
}

sub printForm() {
	print <<EOD
  <FORM ACTION="index.cgi">
    <table border="0">
      <tr>
        <td>Name to look up:</td>
        <td><input type="text" name="name" width="30"></td>
      </tr>
      <tr>
        <td valign="top">Type:</td>
        <td><input type="text" name="type" width="30"></td>
      </tr>
      <tr>
        <td>Output format:</td>
        <td><input type="radio" name="format" value="html" checked>HTML<br>
	    <input type="radio" name="format" value="json">JSON<br>
      </tr>
      <tr>
        <td>Lookup type:</td>
        <td><input type="radio" name="lookup" value="normal" checked>Normal<br>
	    <input type="radio" name="lookup" id="doh" value="doh">DNS-over-HTTPS<br>
      </tr>
      <tr>
        <td>ECS Country Netblock (implies DoH):</td>
        <td><select name="country" onchange="if (this.selectedIndex) document.getElementById('doh').checked = true;">
            <option value="none">
EOD
;
	foreach my $c (@COUNTRIES) {
		print "            <option value=\"$c\">$c\n";
	}
	print <<EOD
        </td>
      </tr>
      <tr>
        <td colspan="2">
          <input type="submit" value="Submit">
        </td>
      </tr>
    </table>
  </FORM>
EOD
;
}

###
### Main
###

my $format = $CGI->param('format');
if (!$format || $format eq "html") {
	printHead();
}

if (!$format) {
	printInstructions();
	printForm();
} else {
	runPuddy();
	if ($format eq "html") {
		print '  <hr width="75%">';
		printForm();
	}
}

if (!$format || $format eq "html") {
	printFoot();
}
