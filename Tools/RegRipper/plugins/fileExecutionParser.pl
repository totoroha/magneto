#--------------------------------------------------------------------------------
# appcompatcache.pl, userassist.pl, runmru.pl, shimcache.pl, bam.pl, recentapps.pl
#--------------------------------------------------------------------------------
package fileExecutionParser;
use strict;
use Excel::Writer::XLSX;
use Time::Local;

my %config = (hive          => "System",
							hivemask      => 4,
							output        => "report",
							category      => "Program Execution",
              hasShortDescr => 1,
              hasDescr      => 0,
              hasRefs       => 0,
              osmask        => 31,  #XP - Win7
              version       => 20160528);

sub getConfig{return %config}
sub getShortDescr {
	return "Parse files from System hive AppCompatCache";
}
sub getDescr{}
sub getRefs {}
sub getHive {return $config{hive};}
sub getVersion {return $config{version};}

my $VERSION = getVersion();
my %files;
my $str = "";

sub pluginmain {
	my $class = shift;
	my $user = shift;
	my $software = $user;
	my $amcache = $user;
	my $output = $user;
	$output =~ s/(.*\\)([^\\]*)_(USER_[^\\]*).dat$/$1/g;
	$amcache =~ s/(.*\\)([^\\]*)_(USER_[^\\]*).dat$/$1\\AmCache\\Amcache.hve/g;
	$software =~ s/(.*\\)([^\\]*)_(USER_[^\\]*).dat$/$1SOFTWARE_$2.hiv/g;
	my $system = $software;
	$system =~ s/(.*)SOFTWARE([^\\]*$)/$1SYSTEM$2/g;
	my $reg = Parse::Win32Registry->new($system);
	my $root_key = $reg->get_root_key;

	#Create an excel sheet for each plugin
	#appcompatcache.pl
	my $fileexecution_workbook = Excel::Writer::XLSX->new($output.'FileExecution.xlsx');
	my $appcompatcache_worksheet = $fileexecution_workbook->add_worksheet('AppCompatCache');
	$appcompatcache_worksheet->write(0,0,"Path");
	$appcompatcache_worksheet->write(0,1,"Last Modified");
	$appcompatcache_worksheet->write(0,2,"Last Updated");
	$appcompatcache_worksheet->write(0,3,"Size");
	$appcompatcache_worksheet->write(0,4,"Exec Flag");

	#userassist.pl	
	my $userassist_worksheet = $fileexecution_workbook->add_worksheet('UserAssist');
	$userassist_worksheet->write(0,0,"Path");
	$userassist_worksheet->write(0,1,"Launch Location");
	$userassist_worksheet->write(0,2,"Last Executed");
	$userassist_worksheet->write(0,3,"User");
	
	#runmru.pl
	my $runmru_worksheet = $fileexecution_workbook->add_worksheet('RunMRU');
	$runmru_worksheet->write(0,0,"Program Name");
	$runmru_worksheet->write(0,1,"User");
	
	#amcache.pl
	my $amcache_worksheet = $fileexecution_workbook->add_worksheet('AmCache');
	$amcache_worksheet->write(0,0,"Path");
	$amcache_worksheet->write(0,1,"SHA1");
	$amcache_worksheet->write(0,2,"First Executed");
	$amcache_worksheet->write(0,3,"Volume GUID");

	#bam.pl 
	my $bam_worksheet = $fileexecution_workbook->add_worksheet('BAM');
	$bam_worksheet->write(0,0,"Path");
	$bam_worksheet->write(0,1,"Last Executed");
	$bam_worksheet->write(0,2,"User");

	#recentapps.pl
	my $recentapps_worksheet = $fileexecution_workbook->add_worksheet('RecentApps');
	$recentapps_worksheet->write(0,0,"Path");
	$recentapps_worksheet->write(0,1,"Last Executed");
	$recentapps_worksheet->write(0,2,"User");
	
	my $row = 1;
# First thing to do is get the ControlSet00x marked current...this is
# going to be used over and over again in plugins that access the system
# file
	my ($current,$ccs);
	my $key_path = 'Select';
	my $key;
	if ($key = $root_key->get_subkey($key_path)) {
		$current = $key->get_value("Current")->get_data();
		$ccs = "ControlSet00".$current;
		my $appcompat_path = $ccs."\\Control\\Session Manager";
		my $appcompat;
		if ($appcompat = $root_key->get_subkey($appcompat_path)) {

			my $app_data;

			eval {
				$app_data = $appcompat->get_subkey("AppCompatibility")->get_value("AppCompatCache")->get_data();
				::rptMsg($appcompat_path."\\AppCompatibility");
			  	::rptMsg("LastWrite Time: ".gmtime($appcompat->get_subkey("AppCompatibility")->get_timestamp())." Z");
			};

			eval {
				$app_data = $appcompat->get_subkey("AppCompatCache")->get_value("AppCompatCache")->get_data();
				::rptMsg($appcompat_path."\\AppCompatCache");
			  	::rptMsg("LastWrite Time: ".gmtime($appcompat->get_subkey("AppCompatCache")->get_timestamp())." Z");
			};

#			::rptMsg("Length of data: ".length($app_data));
#			probe($app_data);
			my $sig = unpack("V",substr($app_data,0,4));
			::rptMsg(sprintf "Signature: 0x%x",$sig);

			if ($sig == 0xdeadbeef) {
				eval {
					appXP32Bit($app_data);
				};
			}
			elsif ($sig == 0xbadc0ffe) {
				eval {
					appWin2k3($app_data);
				};
			}
			elsif ($sig == 0xbadc0fee) {
				eval {
					appWin7($app_data);
				};

			}
			elsif ($sig == 0x80) {
#				::rptMsg("Possible Win8 system\.");
#				::rptMsg(sprintf "Data Length: 0x%08x",length($app_data));
				appWin8($app_data);
#				probe($app_data);

			}
			elsif ($sig == 0x30 || $sig == 0x34) {
# Windows 10 system
				appWin10($app_data);
			}
			else {
				::rptMsg(sprintf "Unknown signature: 0x%x",$sig);
			}
# this is where we print out the files
			foreach my $f (keys %files) {
				my $modtime = $files{$f}{modtime};
				if ($modtime == 0) {
					$modtime = "";
				}
				else {
					$modtime = gmtime($modtime)." Z";
				}
				$appcompatcache_worksheet->write($row,1,$modtime);
				$appcompatcache_worksheet->write($row,0,$files{$f}{filename});
				$appcompatcache_worksheet->write($row,2,gmtime($files{$f}{updtime})." Z") if (exists $files{$f}{updtime});
				$appcompatcache_worksheet->write($row,4,"Executed") if (exists $files{$f}{executed});
				$row++;
			}
		}
	}

	my %userDictionary;
	$reg = Parse::Win32Registry->new($software);
	$root_key = $reg->get_root_key;
	$key_path = "Microsoft\\Windows NT\\CurrentVersion\\ProfileList";
	if(my $key = $root_key->get_subkey($key_path)) {
		my @subkeys = $key->get_list_of_subkeys();
		if (scalar(@subkeys) > 0) {
			foreach my $s (@subkeys) {
				my $profilePath;
				eval {
					$profilePath = $s->get_value("ProfileImagePath")->get_data();
				};
				my @dataArray = split /\\/, $profilePath;
				if ($dataArray[1] eq "Users") {
					$userDictionary{$s->get_name()} = $dataArray[2];
				}
			}
		}
	}

	my %userMapping;
	my $filename = $system;
	$filename =~ s/(.*)SYSTEM[^\\]*$/$1USERMapping.txt/g;
	open(my $userFile, "<", $filename);
	while ( my $line = <$userFile> ) {
		my $who;
		my $rest;
		my $temp;
	    ($who, $rest) = split /:\s*/, $line, 2;
	    ($temp, $who) = split /\\/, $who, 2;
	    $userMapping{$rest} = $who;
	}

	$row = 1;
	eval {
		$reg = Parse::Win32Registry->new($amcache);
		$root_key = $reg->get_root_key;
		my @sk1;
		my @sk;
		my (@t,$gt);
		
		$key_path = 'Root\\File';
		if ($key = $root_key->get_subkey($key_path)) {
			
			@sk1 = $key->get_list_of_subkeys();
			foreach my $s1 (@sk1) {
	# Volume GUIDs			
				my $volguid = $s1->get_name();
				
				@sk = $s1->get_list_of_subkeys();
				if (scalar(@sk) > 0) {
					foreach my $s (@sk) {
						# $worksheet->write($row,15,$s->get_value("15")->get_data());
						# $worksheet->write($row,16,$s->get_value("101")->get_data());
						# $worksheet->write($row,17,gmtime($s->get_timestamp())." Z");
						# $worksheet->write($row,18,$volguid);

						$amcache_worksheet->write($row,0,$s->get_value("15")->get_data());
						$amcache_worksheet->write($row,1,$s->get_value("101")->get_data());
						$amcache_worksheet->write($row,2,gmtime($s->get_timestamp())." Z");
						$amcache_worksheet->write($row,3,$volguid);

						$row++;
					}
				}	
			}
		}
		else {
			::rptMsg($key_path." not found.");
		}
	};

	$row = 1;
	#Volume GUID => User Name
	my %ownerDictionary;
	my @userNumbers = keys %userMapping;
	foreach my $userNumber (@userNumbers) {
		#S20-15-21....
		my $userId = $userMapping{$userNumber};
		my $currentNumber = $userNumber;
		chomp $currentNumber;
		$user =~ s/(.*\\)([^\\]*)_(USER_[^\\]*).dat$/$1$2_$currentNumber.dat/g;
		$reg = Parse::Win32Registry->new($user);
		$root_key = $reg->get_root_key;
		$key_path = "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\UserAssist";
		if (my $key = $root_key->get_subkey($key_path)) {
			my @subkeys = $key->get_list_of_subkeys();
			if (scalar(@subkeys) > 0) {
				foreach my $s (@subkeys) {
					my %ua = processKey($s);
					foreach my $t (reverse sort {$a <=> $b} keys %ua) {
						foreach my $i (@{$ua{$t}}) {
							# $worksheet->write($row,7,gmtime($t)." Z");
							# $worksheet->write($row,8,$userDictionary{$userId});
							# $worksheet->write($row,6,$s->get_name());
							# $worksheet->write($row,5,$i);

							$userassist_worksheet->write($row,2,gmtime($t)." Z");
							if($userDictionary{$userId}) {
								$userassist_worksheet->write($row,3,$userDictionary{$userId});
							}
							else {
								$userassist_worksheet->write($row,3,$userId);
							}
							$userassist_worksheet->write($row,1,$s->get_name());
							$userassist_worksheet->write($row,0,$i);
							$row++;	
						}
					}
				}
			}
		}

		# $key_path = "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ComDlg32";
		# if (my $key = $root_key->get_subkey($key_path)) {
		# 	my @subkeys = $key->get_list_of_subkeys();

		# 	if (scalar @subkeys > 0) {
		# 		foreach my $s (@subkeys) {
		# 			if ($s->get_name() eq "LastVisitedMRU") {
		# 				$row = 1;
		# 				parseLastVisitedMRU($s, $row, $lastvistedmru_worksheet, $userDictionary{$userId});
		# 			}

		# 			if ($s->get_name() eq "LastVisitedPidlMRU" || $s->get_name() eq "LastVisitedPidlMRULegacy") {
		# 				$row = 1;
		# 				parseLastVisitedPidlMRU($s, $row, $lastvistedmru_worksheet, $userDictionary{$userId});
		# 			}
		# 		}
		# 	}
		# }

		$row = 1;
		$key_path = 'Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\RunMRU';
		if (my $key = $root_key->get_subkey($key_path)) {
			my @vals = $key->get_list_of_values();
			my %runvals;
			my $mru;
			if (scalar(@vals) > 0) {
				foreach my $v (@vals) {
					$runvals{$v->get_name()} = $v->get_data() unless ($v->get_name() eq "MRUList");
					$mru = $v->get_data() if ($v->get_name() eq "MRUList");
				}
				foreach my $r (sort keys %runvals) {
					# $worksheet->write($row,13,$runvals{$r});
					# $worksheet->write($row,14,$userDictionary{$userId});

					$runmru_worksheet->write($row,0,$runvals{$r});
					if($userDictionary{$userId}) {
						$runmru_worksheet->write($row,1,$userDictionary{$userId});
					}
					else {
						$runmru_worksheet->write($row,1,$userId);
					}			
					$row++;
				}
			}
		}

		#RecentApps
		$row = 1;
		$key_path = 'Software\\Microsoft\\Windows\\CurrentVersion\\Search\\RecentApps';
		if (my $key = $root_key->get_subkey($key_path)) {
			my @subkeys = $key->get_list_of_subkeys();
			if (scalar(@subkeys) > 0) {
				foreach my $s (@subkeys) { 
					eval {
						$recentapps_worksheet->write($row,0,$s->get_value("AppId")->get_data());
						my ($t1,$t2) = unpack("VV",$s->get_value("LastAccessedTime")->get_data());
						my $lat = ::getTime($t1,$t2);
						my $last_exec = "".gmtime($lat)."UTC";
						$recentapps_worksheet->write($row,1,$last_exec);
						if($userDictionary{$userId}) {
							$recentapps_worksheet->write($row,2,$userDictionary{$userId});
						}
						else {
							$recentapps_worksheet->write($row,2,$userId);
						}
					};
					$row++;
				}
			}
		}
	}

	#BAM
	$row = 1;
	$reg = Parse::Win32Registry->new($system);
	$root_key = $reg->get_root_key;
# First thing to do is get the ControlSet00x marked current...this is
# going to be used over and over again in plugins that access the system
# file
	my ($current,$ccs);
	$key_path = 'Select';
	if ($key = $root_key->get_subkey($key_path)) {
		$current = $key->get_value("Current")->get_data();
		$ccs = "ControlSet00".$current;
		my $bam_path = $ccs."\\Services\\bam\\UserSettings";
		my $bam;
		if ($bam = $root_key->get_subkey($bam_path)) {
			my @sk = $bam->get_list_of_subkeys();
			if (scalar(@sk) > 0) {
				foreach my $s (@sk) {
					my %result = bam_processKey($s);
					foreach my $k (keys %result) {
						$bam_worksheet->write($row,0,$k);
						$bam_worksheet->write($row,1,$result{$k});
						if($userDictionary{$s->get_name()}) {
							$bam_worksheet->write($row,2,$userDictionary{$s->get_name()});
						}
						else {
							$bam_worksheet->write($row,2,$s->get_name());
						}
						$row++;
					} 
				}
			}	
		}
	}


	$fileexecution_workbook->close();
}

sub bam_processKey {
	my $key = shift;
	my ($t,$count);
	my @values = $key->get_list_of_values();
	my %result;

	foreach (@values) {
		$count = 1 if ($_->get_type() == 3);
	}
	
	if (scalar(@values) > 0 && $count == 1) {
#		::rptMsg($key->get_name());
		foreach my $v (@values) {
			my $name = $v->get_name();
			if ($v->get_type() == 3) {
				my ($t0,$t1) = unpack("VV",substr($v->get_data(),0,8));
				$t = ::getTime($t0,$t1);
				$result{$name} = gmtime($t);
#				::rptMsg("  ".gmtime($t)." - ".$name);
			}
				
		}
#		::rptMsg("");
		return %result;
	}		
}

#-----------------------------------------------------------
# appXP32Bit()
# parse 32-bit XP data
#-----------------------------------------------------------
sub appXP32Bit {
	my $data = shift;
	::rptMsg("WinXP, 32-bit");
# header is 400 bytes; each structure is 552 bytes in size
	my $num_entries = unpack("V",substr($data,4,4));

	foreach my $i (0..($num_entries - 1)) {
		my $x = substr($data,(400 + ($i * 552)),552);
		my $file = (split(/\00\00/,substr($x,0,488)))[0];
		$file =~ s/\00//g;
		$file =~ s/^\\\?\?\\//;
		my ($mod1,$mod2) = unpack("VV",substr($x,528,8));
		my $modtime      = ::getTime($mod1,$mod2);
		my ($sz1,$sz2)   = unpack("VV",substr($x,536,8));
		my $sz;
		($sz2 == 0)?($sz = $sz1):($sz = "Too big");
		my ($up1,$up2)   = unpack("VV",substr($x,544,8));
		my $updtime      = ::getTime($up1,$up2);

		$files{$i}{filename} = $file;
		$files{$i}{size} = $sz;
		$files{$i}{modtime} = $modtime;
		$files{$i}{updtime} = $updtime;
	}
}
#-----------------------------------------------------------
# appWin2k3()
# parse Win2k3, Vista, Win2k8 data
#-----------------------------------------------------------
sub appWin2k3 {
	my $data = shift;
	my $num_entries = unpack("V",substr($data,4,4));
#	::rptMsg("Num_entries: ".$num_entries);
	my $struct_sz = 0;
	my ($len,$max_len,$padding) = unpack("vvV",substr($data,8,8));
	if (($max_len - $len) == 2) {
# if $padding == 0, 64-bit; otherwise, 32-bit
		if ($padding == 0) {
			$struct_sz = 32;
			::rptMsg("Win2K3/Vista/Win2K8, 64-bit");
		}
		else {
			$struct_sz = 24;
			::rptMsg("Win2K3/Vista/Win2K8, 32-bit");
		}
	}

	foreach my $i (0..($num_entries - 1)) {
		my $struct = substr($data,(8 + ($struct_sz * $i)),$struct_sz);
		if ($struct_sz == 24) {
			my ($len,$max_len,$ofs,$t0,$t1,$f0,$f1) = unpack("vvVVVVV",$struct);

			my $file = substr($data,$ofs,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
			$files{$i}{filename} = $file;
			$files{$i}{modtime} = $t;
			$files{$i}{size} = $f0 if (($f1 == 0) && ($f0 > 3));
			$files{$i}{executed} = 1 if (($f0 < 4) && ($f0 & 0x2));
		}
		elsif ($struct_sz == 32) {
			my ($len,$max_len,$padding,$ofs0,$ofs1,$t0,$t1,$f0,$f1) = unpack("vvVVVVVVV",$struct);
			my $file = substr($data,$ofs0,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
			$files{$i}{filename} = $file;
			$files{$i}{modtime} = $t;
			$files{$i}{size} = $f0 if (($f1 == 0) && ($f0 > 3));
			$files{$i}{executed} = 1 if (($f0 < 4) && ($f0 & 0x2));
		}
		else {
#
		}
	}
}

#-----------------------------------------------------------
# appWin7()
# parse Win2k8R2, Win7 data
#-----------------------------------------------------------
sub appWin7 {
	my $data = shift;
	my $struct_sz = 0;
	my $num_entries = unpack("V",substr($data,4,4));
#	::rptMsg("Num_entries: ".$num_entries);
# 128-byte header
	my ($len,$max_len,$padding) = unpack("vvV",substr($data,128,8));
	if (($max_len - $len) == 2) {
		if ($padding == 0) {
			$struct_sz = 48;
			::rptMsg("Win2K8R2/Win7, 64-bit");
		}
		else {
			$struct_sz = 32;
			::rptMsg("Win2K8R2/Win7, 32-bit");
		}
	}

	foreach my $i (0..($num_entries - 1)) {
		my $struct = substr($data,(128 + ($struct_sz * $i)),$struct_sz);
		if ($struct_sz == 32) {
			my ($len,$max_len,$ofs,$t0,$t1,$f0,$f1) = unpack("vvV5x8",$struct);
			my $file = substr($data,$ofs,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
 			$files{$i}{filename} = $file;
			$files{$i}{modtime} = $t;
			$files{$i}{executed} = 1 if ($f0 & 0x2);
		}
		else {
			my ($len,$max_len,$padding,$ofs0,$ofs1,$t0,$t1,$f0,$f1) = unpack("vvV7x16",$struct);
			my $file = substr($data,$ofs0,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
 			$files{$i}{filename} = $file;
			$files{$i}{modtime} = $t;
			$files{$i}{executed} = 1 if ($f0 & 0x2);
		}
	}
}

#-----------------------------------------------------------
# appWin8()
#-----------------------------------------------------------
sub appWin8 {
	my $data = shift;
	my $len = length($data);
	my ($jmp, $t0, $t1, $sz, $name);
	my $ct = 0;
	my $ofs = unpack("V",substr($data,0,4));

	while($ofs < $len) {
		my $tag = unpack("V",substr($data,$ofs,4));
# 32-bit
		if ($tag == 0x73746f72) {
			$jmp = unpack("V",substr($data,$ofs + 8,4));
			($t0,$t1) = unpack("VV",substr($data,$ofs + 12,8));
			$sz = unpack("v",substr($data,$ofs + 20,2));
			$name = substr($data,$ofs + 22,$sz);
			$name =~ s/\00//g;
			$files{$ct}{filename} = $name;
			$files{$ct}{modtime} = ::getTime($t0,$t1);
			$ct++;
			$ofs += ($jmp + 12);
		}
# 64-bit
		elsif ($tag == 0x73743030 || $tag == 0x73743031) {
			$jmp = unpack("V",substr($data,$ofs + 8,4));
			$sz = unpack("v",substr($data,$ofs + 0x0C,2));
			$name = substr($data,$ofs + 0x0E,$sz + 2);
			$name =~ s/\00//g;
			($t0,$t1) = unpack("VV",substr($data,($ofs + 0x0E + $sz +2 + 8),8));
			$files{$ct}{filename} = $name;
			$files{$ct}{modtime} = ::getTime($t0,$t1);
			$ct++;
			$ofs += ($jmp + 12);
		}
		else {
# Unknown tag
		}

	}
}

#-----------------------------------------------------------
# appWin10()
# Ref: http://binaryforay.blogspot.com/2015/04/appcompatcache-changes-in-windows-10.html
#-----------------------------------------------------------
sub appWin10 {
	my $data = shift;
	my $len = length($data);
	my ($tag, $sz, $t0, $t1, $name, $name_len);
	my $ct = 0;
	my $ofs = unpack("V",substr($data,0,4));

	while ($ofs < $len) {
		$tag = substr($data,$ofs,4);
		if ($tag eq "10ts") {

			$sz = unpack("V",substr($data,$ofs + 0x08,4));
			$name_len   = unpack("v",substr($data,$ofs + 0x0c,2));
			my $name      = substr($data,$ofs + 0x0e,$name_len);
			$name =~ s/\00//g;
#			($t0,$t1) = unpack("VV",substr($data,$ofs + 0x03 + $name_len,8));
			($t0,$t1) = unpack("VV",substr($data,$ofs + 0x0e + $name_len,8));
			$files{$ct}{filename} = $name;
			$files{$ct}{modtime} = ::getTime($t0,$t1);
			$ct++;
			$ofs += ($sz + 0x0c);
		}
	}
}

#-----------------------------------------------------------
# alertCheckPath()
#-----------------------------------------------------------
sub alertCheckPath {
	my $path = shift;
	$path = lc($path);
	my @alerts = ("recycle","globalroot","temp","system volume information","appdata",
	              "application data");

	foreach my $a (@alerts) {
		if (grep(/$a/,$path)) {
			::alertMsg("ALERT: appcompatcache: ".$a." found in path: ".$path);
		}
	}
}

#-----------------------------------------------------------
# alertCheckADS()
#-----------------------------------------------------------
sub alertCheckADS {
	my $path = shift;
	my @list = split(/\\/,$path);
	my $last = $list[scalar(@list) - 1];
	::alertMsg("ALERT: appcompatcache: Poss. ADS found in path: ".$path) if grep(/:/,$last);
}


#-----------------------------------------------------------
# probe()
#
# Code the uses printData() to insert a 'probe' into a specific
# location and display the data
#
# Input: binary data of arbitrary length
# Output: Nothing, no return value.  Displays data to the console
#-----------------------------------------------------------
sub probe {
	my $data = shift;
	my @d = printData($data);

	foreach (0..(scalar(@d) - 1)) {
		print $d[$_]."\n";
	}
}

#-----------------------------------------------------------
# printData()
# subroutine used primarily for debugging; takes an arbitrary
# length of binary data, prints it out in hex editor-style
# format for easy debugging
#-----------------------------------------------------------
sub printData {
	my $data = shift;
	my $len = length($data);

	my @display = ();

	my $loop = $len/16;
	$loop++ if ($len%16);

	foreach my $cnt (0..($loop - 1)) {
# How much is left?
		my $left = $len - ($cnt * 16);

		my $n;
		($left < 16) ? ($n = $left) : ($n = 16);

		my $seg = substr($data,$cnt * 16,$n);
		my $lhs = "";
		my $rhs = "";
		foreach my $i ($seg =~ m/./gs) {
# This loop is to process each character at a time.
			$lhs .= sprintf(" %02X",ord($i));
			if ($i =~ m/[ -~]/) {
				$rhs .= $i;
    	}
    	else {
				$rhs .= ".";
     	}
		}
		$display[$cnt] = sprintf("0x%08X  %-50s %s",$cnt,$lhs,$rhs);

	}
	return @display;
}

sub processKey {
	my $ua = shift;
	my $key = $ua->get_subkey("Count");
	my %ua;
	my $hrzr = "HRZR";
	my @vals = $key->get_list_of_values();
	if (scalar(@vals) > 0) {
		foreach my $v (@vals) {
			my $value_name = $v->get_name();
			my $data = $v->get_data();

# Windows XP/2003/Vista/2008
			if (length($data) == 16) {
				my ($session,$count,$val1,$val2) = unpack("V*",$data);
			 	if ($val2 != 0) {
					my $time_value = ::getTime($val1,$val2);
					if ($value_name =~ m/^$hrzr/) {
						$value_name =~ tr/N-ZA-Mn-za-m/A-Za-z/;
					}
					$count -= 5 if ($count > 5);
					push(@{$ua{$time_value}},$value_name." (".$count.")");
				}
			}
# Windows 7
			elsif (length($data) == 72) {
				$value_name =~ tr/N-ZA-Mn-za-m/A-Za-z/;
				my $count = unpack("V",substr($data,4,4));
				my @t = unpack("VV",substr($data,60,8));
				next if ($t[0] == 0 && $t[1] == 0);
				my $time_val = ::getTime($t[0],$t[1]);
				push(@{$ua{$time_val}},$value_name." (".$count.")");
			}
			else {
# Nothing else to do
			}
		}
		return %ua;
	}
}

sub parseSystemFolderEntry {
	my $data     = shift;
	my %item = ();

	my %vals = (0x00 => "Explorer",
	            0x42 => "Libraries",
	            0x44 => "Users",
	            0x4c => "Public",
	            0x48 => "My Documents",
	            0x50 => "My Computer",
	            0x58 => "My Network Places",
	            0x60 => "Recycle Bin",
	            0x68 => "Explorer",
	            0x70 => "Control Panel",
	            0x78 => "Recycle Bin",
	            0x80 => "My Games");

	$item{type} = unpack("C",substr($data,2,1));
	$item{id}   = unpack("C",substr($data,3,1));
	if (exists $vals{$item{id}}) {
		$item{name} = $vals{$item{id}};
	}
	else {
		$item{name} = parseGUID(substr($data,4,16));
	}
	return %item;
}

#-----------------------------------------------------------
# parseGUID()
# Takes 16 bytes of binary data, returns a string formatted
# as an MS GUID.
#-----------------------------------------------------------
sub parseGUID {
	my $data     = shift;
  my $d1 = unpack("V",substr($data,0,4));
  my $d2 = unpack("v",substr($data,4,2));
  my $d3 = unpack("v",substr($data,6,2));
	my $d4 = unpack("H*",substr($data,8,2));
  my $d5 = unpack("H*",substr($data,10,6));
  return sprintf "{%08x-%x-%x-$d4-$d5}",$d1,$d2,$d3;
}

#-----------------------------------------------------------
#
#-----------------------------------------------------------
sub parseDriveEntry {
	my $data     = shift;
	my %item = ();
	$item{type} = unpack("C",substr($data,2,1));;
	$item{name} = substr($data,3,3);
	return %item;
}
#-----------------------------------------------------------
# parseNetworkEntry()
#
#-----------------------------------------------------------
sub parseNetworkEntry {
	my $data = shift;
	my %item = ();
	$item{type} = unpack("C",substr($data,2,1));

	my @n = split(/\x00/,substr($data,4,length($data) - 4));
	$item{name} = $n[0];
	$item{name} =~ s/^\W//;
	return %item;
}
#-----------------------------------------------------------
#
#-----------------------------------------------------------
sub parseFolderEntry {
	my $data     = shift;
	my %item = ();

	$item{type} = unpack("C",substr($data,2,1));
# Type 0x74 folders have a slightly different format

	my $ofs_mdate;
	my $ofs_shortname;

	if ($item{type} == 0x74) {
		$ofs_mdate = 0x12;
	}
	elsif (substr($data,4,4) eq "AugM") {
		$ofs_mdate = 0x1c;
	}
	elsif ($item{type} == 0x31 || $item{type} == 0x32 || $item{type} == 0x3a) {
		$ofs_mdate = 0x08;
	}
	else {}
# some type 0x32 items will include a file size
	if ($item{type} == 0x32) {
		my $size = unpack("V",substr($data,4,4));
		if ($size != 0) {
			$item{filesize} = $size;
		}
	}

	my @m = unpack("vv",substr($data,$ofs_mdate,4));
	($item{mtime_str},$item{mtime}) = convertDOSDate($m[0],$m[1]);

# Need to read in short name; nul-term ASCII
#	$item{shortname} = (split(/\x00/,substr($data,12,length($data) - 12),2))[0];
	$ofs_shortname = $ofs_mdate + 6;
	my $tag = 1;
	my $cnt = 0;
	my $str = "";
	while($tag) {
		my $s = substr($data,$ofs_shortname + $cnt,1);
		if ($s =~ m/\x00/ && ((($cnt + 1) % 2) == 0)) {
			$tag = 0;
		}
		else {
			$str .= $s;
			$cnt++;
		}
	}
#	$str =~ s/\x00//g;
	my $shortname = $str;
	my $ofs = $ofs_shortname + $cnt + 1;
# Read progressively, 1 byte at a time, looking for 0xbeef
	$tag = 1;
	$cnt = 0;
	while ($tag) {
		if (unpack("v",substr($data,$ofs + $cnt,2)) == 0xbeef) {
			$tag = 0;
		}
		else {
			$cnt++;
		}
	}
	$item{extver} = unpack("v",substr($data,$ofs + $cnt - 4,2));

#	::rptMsg(sprintf "  BEEF Offset: 0x%x",$ofs + $cnt);
#	::rptMsg("  Version: ".$item{extver});

	$ofs = $ofs + $cnt + 2;

	@m = unpack("vv",substr($data,$ofs,4));
	($item{ctime_str},$item{ctime}) = convertDOSDate($m[0],$m[1]);
	$ofs += 4;
	@m = unpack("vv",substr($data,$ofs,4));
	($item{atime_str},$item{atime}) = convertDOSDate($m[0],$m[1]);
	$ofs += 4;

	my $jmp;
	if ($item{extver} == 0x03) {
		$jmp = 8;
	}
	elsif ($item{extver} == 0x07) {
		$jmp = 22;
	}
	elsif ($item{extver} == 0x08) {
		$jmp = 26;
	}
	else {}

	$ofs += $jmp;
#	::rptMsg(sprintf "  Offset: 0x%x",$ofs);

	$str = substr($data,$ofs,length($data) - $ofs);

	my $longname = (split(/\x00\x00/,$str,2))[0];
	$longname =~ s/\x00//g;

	if ($longname ne "") {
		$item{name} = $longname;
	}
	else {
		$item{name} = $shortname;
	}
	return %item;
}
#-----------------------------------------------------------
# convertDOSDate()
# subroutine to convert 4 bytes of binary data into a human-
# readable format.  Returns both a string and a Unix-epoch
# time.
#-----------------------------------------------------------
sub convertDOSDate {
	my $date = shift;
	my $time = shift;

	if ($date == 0x00 || $time == 0x00){
		return (0,0);
	}
	else {
		my $sec = ($time & 0x1f) * 2;
		$sec = "0".$sec if (length($sec) == 1);
		if ($sec == 60) {$sec = 59};
		my $min = ($time & 0x7e0) >> 5;
		$min = "0".$min if (length($min) == 1);
		my $hr  = ($time & 0xF800) >> 11;
		$hr = "0".$hr if (length($hr) == 1);
		my $day = ($date & 0x1f);
		$day = "0".$day if (length($day) == 1);
		my $mon = ($date & 0x1e0) >> 5;
		$mon = "0".$mon if (length($mon) == 1);
		my $yr  = (($date & 0xfe00) >> 9) + 1980;
		my $gmtime = timegm($sec,$min,$hr,$day,($mon - 1),$yr);
    return ("$yr-$mon-$day $hr:$min:$sec",$gmtime);
#		return gmtime(timegm($sec,$min,$hr,$day,($mon - 1),$yr));
	}
}
#-----------------------------------------------------------
# probe()
#
# Code the uses printData() to insert a 'probe' into a specific
# location and display the data
#
# Input: binary data of arbitrary length
# Output: Nothing, no return value.  Displays data to the console
#-----------------------------------------------------------
sub probe {
	my $data = shift;
	my @d = printData($data);

	foreach (0..(scalar(@d) - 1)) {
		print $d[$_]."\n";
	}
}

1;
