#-----------------------------------------------------------
# amcache.pl 
#   
# Change history
#   20160818 - added check for value 17
#   20131218 - fixed bug computing compile time
#   20131213 - updated 
#   20131204 - created
#
# References
#   http://www.swiftforensics.com/2013/12/amcachehve-in-windows-8-goldmine-for.html
#
# Copyright (c) 2013 QAR, LLC
# Author: H. Carvey, keydet89@yahoo.com
#-----------------------------------------------------------
package amcache;
use strict;
use Excel::Writer::XLSX;
use Time::Piece;
use Regexp::Common qw(time);

my %config = (hive          => "amcache",
              hasShortDescr => 1,
              hasDescr      => 1,
              hasRefs       => 1,
              osmask        => 22,
              category      => "program execution",
              version       => 20160818);
my $VERSION = getVersion();

# Functions #
sub getConfig {return %config}
sub getHive {return $config{hive};}
sub getVersion {return $config{version};}
sub getDescr {}
sub getShortDescr {
	return "Parse AmCache.hve file";
}
sub getRefs {}

sub pluginmain {
	my $class = shift;
	my $hive = shift;

	# Initialize #
	::logMsg("Launching amcache v.".$VERSION);
	::rptMsg("amcache v.".$VERSION); 
	::rptMsg("(".$config{hive}.") ".getShortDescr()."\n");     
	my $reg = Parse::Win32Registry->new($hive);
	my $root_key = $reg->get_root_key;
	my $key;
	my @sk1;
	my @sk;
	my (@t,$gt);

	my $workbook_name = $hive;
	$workbook_name =~ s/(.*\\)Amcache.hve$/$1Timeline-Amcache.xlsx/g;
	my $workbook = Excel::Writer::XLSX->new($workbook_name);
	my $worksheet = $workbook->add_worksheet();
	my $row = 0;
	
	my $key_path = 'Root\\File';
	::rptMsg("***Files***");
	if ($key = $root_key->get_subkey($key_path)) {
		
		@sk1 = $key->get_list_of_subkeys();
		foreach my $s1 (@sk1) {
# Volume GUIDs			
			::rptMsg($s1->get_name());
			
			@sk = $s1->get_list_of_subkeys();
			if (scalar(@sk) > 0) {
				foreach my $s (@sk) {
					::rptMsg("File Reference: ".$s->get_name());
					::rptMsg("LastWrite     : ".gmtime($s->get_timestamp())." Z");
					my $lastwritetime = gmtime($s->get_timestamp());
					my $lastwritetime_parsed;
					if ($lastwritetime !~ m/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) {2,}/) {
						my @date = $lastwritetime =~ $RE{time}{strftime}{-pat => '%a %b %d %H:%M:%S %Y'}{-keep};
			   			$lastwritetime_parsed = Time::Piece->strptime($date[0], '%a %b %d %H:%M:%S %Y');
			   		} else {
			   			my @parse = $lastwritetime =~ m/(Mon|Tue|Wed|Thu|Fri|Sat|Sun)(.*)/;
			   			$lastwritetime = $parse[0].$parse[1];
			   			$lastwritetime_parsed = Time::Piece->strptime($lastwritetime, '%a %b  %d %H:%M:%S %Y');
			   		}
# update 20131213: based on trial and error, it appears that not all file
# references will have all of the values, such as Path, or SHA-1		
					eval {
						::rptMsg("Path          : ".$s->get_value("15")->get_data());
					};
					
					eval {
						::rptMsg("Company Name  : ".$s->get_value("1")->get_data());
					};
					
					eval {
						::rptMsg("SHA-1         : ".$s->get_value("101")->get_data());
					};
					
					eval {
						@t = unpack("VV",$s->get_value("11")->get_data());
						$gt = gmtime(::getTime($t[0],$t[1]));
						::rptMsg("Last Mod Time : ".$gt." Z");
					};
					
					eval {
						@t = unpack("VV",$s->get_value("17")->get_data());
						$gt = gmtime(::getTime($t[0],$t[1]));
						::rptMsg("Last Mod Time2: ".$gt." Z");
					};
					
					eval {
						@t = unpack("VV",$s->get_value("12")->get_data());
						$gt = gmtime(::getTime($t[0],$t[1]));
						::rptMsg("Create Time   : ".$gt." Z");
					};
					
					eval {
						$gt = gmtime($s->get_value("f")->get_data());
#						$gt = gmtime(unpack("V",$s->get_value("f")->get_data()));
						::rptMsg("Compile Time  : ".$gt." Z");
					};
					$worksheet->write($row, 0, $lastwritetime_parsed->strftime("%Y-%m-%d"));
					$worksheet->write($row, 1, $lastwritetime_parsed->strftime("%H:%M:%S"));
					$worksheet->write($row, 2, ".A..");
					$worksheet->write($row, 3, "REG");
					$worksheet->write($row, 4, "Amcache.hve Entry");
					$worksheet->write($row, 5, "File First Execution Time");
					my $description = "FILE:".$s->get_value("15")->get_data();
					$worksheet->write($row, 6, $description);
					$description .= " SHA-1:".$s->get_value("101")->get_data();
					$description .= " VOL GUID:".$s1->get_name();
					my $reg_key = $key_path."\\".$s1->get_name()."\\".$s->get_name();
					$worksheet->write($row, 7, "[".$reg_key."] ".$description);
					$row++;
					::rptMsg("");
				}
			}
			else {
#				::rptMsg("Key ".$s1->get_name()." has no subkeys.");
			}		
		}
	}
	else {
		::rptMsg($key_path." not found.");
	}

	$workbook->close();
	
# Root\Programs subkey	
	$key_path = 'Root\\Programs';
	::rptMsg("***Programs***");
	if ($key = $root_key->get_subkey($key_path)) {
		@sk1 = $key->get_list_of_subkeys();
		if (scalar(@sk1) > 0) {
			foreach my $s1 (@sk1) {
				my $str;
				$str = "Name       : ".$s1->get_value("0")->get_data();
				
				eval {
					$str .= " v\.".$s1->get_value("1")->get_data();
				};
				::rptMsg($str);
				eval {
					::rptMsg("Category   : ".$s1->get_value("6")->get_data());
				};
				
				eval {
					::rptMsg("UnInstall  : ".$s1->get_value("7")->get_data());
				};
				
				::rptMsg("");
			}
		}
	}
	else {
		::rptMsg($key_path." not found.");
	}
}

1;
