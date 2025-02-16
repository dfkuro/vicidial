#!/usr/bin/perl
#
# AST_conf_update_3way.pl version 2.14
#
# This script checks leave 3way vicidial_conferences for participants
# This is a constantly running script that is in the keepalive_ALL script, to
# enable this script in the keepalive, add the --cu3way flag to the
# ADMIN_keepalive_ALL.pl entry in the crontab
#
# NOTE: if you are using this script, then you should set the flag in the other
#      script's crontab entry that does some of these functions:
#      AST_conf_update.pl --no-vc-3way-check
#
# Copyright (C) 2023  Matt Florell <vicidial@gmail.com>    LICENSE: AGPLv2
#
# 100811-2119 - First build, based upon AST_conf_update.pl script
# 100928-1506 - Changed from hard-coded 60 minute limit to servers.vicidial_recording_limit
# 130108-1707 - Changes for Asterisk 1.8 compatibility
# 160608-1549 - Added support for AMI version 1.3
# 170222-0939 - Changed to file logging using server settings
# 170921-1814 - Added support for AMI2
# 180420-2301 - Fix for high-volume systems, added varibles to hangup queryCID
# 200413-1356 - Fix for \n\n at the end of PING commands causing errors in AMI
# 231117-2255 - Added AMI version 5 compatibility
# 231118-1110 - Added override option of up to Xtimeout9 for 3WAY_... leave-3way sessions
#

# constants
$DB=0;  # Debug flag
$DBX=0;  # Extra Debug flag
$US='__';
$MT[0]='';
$loops = '100000';
$CLIdelay = '3';

### begin parsing run-time options ###
if (length($ARGV[0])>1)
	{
	$i=0;
	while ($#ARGV >= $i)
		{
		$args = "$args $ARGV[$i]";
		$i++;
		}

	if ($args =~ /--help/i)
		{
		print "allowed run time options:\n";
		print "  [--delay=X] = number of seconds between runs, default = 3\n";
		print "  [-t] = test\n";
		print "  [--debug] = verbose debug messages\n";
		print "  [--debugX] = extra verbose debug messages\n";
		print "\n";
		exit;
		}
	else
		{
		if ($args =~ /-debug/i)
			{
			$DB=1; # Debug flag
			print "-- DEBUGGING ENABLED --\n\n";
			}
		if ($args =~ /-debugX/i)
			{
			$DBX=1; # Extra Debug flag
			print "-- DEBUGGING ENABLED --\n\n";
			}

		if ($args =~ /--delay=/i) # CLI defined delay
			{
			@CLIvarARY = split(/--delay=/,$args);
			@CLIvarARX = split(/ /,$CLIvarARY[1]);
			if (length($CLIvarARX[0])>0)
				{
				$CLIdelay = $CLIvarARX[0];
				$CLIdelay =~ s/\/$| |\r|\n|\t//gi;
				$CLIdelay =~ s/\D//gi;
				if ($DB > 0) {print "Delay set to $CLIdelay\n";}
				}
			@CLIvarARY=@MT;   @CLIvarARY=@MT;
			}

		if ($args =~ /-t/i)
			{
			$TEST=1;
			$T=1;
			}
		}
	}
else
	{
	#	print "no command line options set\n";
	}
### end parsing run-time options ###

if ( ($CLIdelay < 1) || (length($CLIdelay) < 1) )	{$CLIdelay = '1';}

# default path to astguiclient configuration file:
$PATHconf =		'/etc/astguiclient.conf';

open(conf, "$PATHconf") || die "can't open $PATHconf: $!\n";
@conf = <conf>;
close(conf);
$i=0;
foreach(@conf)
	{
	$line = $conf[$i];
	$line =~ s/ |>|\n|\r|\t|\#.*|;.*//gi;
	if ( ($line =~ /^PATHhome/) && ($CLIhome < 1) )
		{$PATHhome = $line;   $PATHhome =~ s/.*=//gi;}
	if ( ($line =~ /^PATHlogs/) && ($CLIlogs < 1) )
		{$PATHlogs = $line;   $PATHlogs =~ s/.*=//gi;}
	if ( ($line =~ /^PATHagi/) && ($CLIagi < 1) )
		{$PATHagi = $line;   $PATHagi =~ s/.*=//gi;}
	if ( ($line =~ /^PATHweb/) && ($CLIweb < 1) )
		{$PATHweb = $line;   $PATHweb =~ s/.*=//gi;}
	if ( ($line =~ /^PATHsounds/) && ($CLIsounds < 1) )
		{$PATHsounds = $line;   $PATHsounds =~ s/.*=//gi;}
	if ( ($line =~ /^PATHmonitor/) && ($CLImonitor < 1) )
		{$PATHmonitor = $line;   $PATHmonitor =~ s/.*=//gi;}
	if ( ($line =~ /^VARserver_ip/) && ($CLIserver_ip < 1) )
		{$VARserver_ip = $line;   $VARserver_ip =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_server/) && ($CLIDB_server < 1) )
		{$VARDB_server = $line;   $VARDB_server =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_database/) && ($CLIDB_database < 1) )
		{$VARDB_database = $line;   $VARDB_database =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_user/) && ($CLIDB_user < 1) )
		{$VARDB_user = $line;   $VARDB_user =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_pass/) && ($CLIDB_pass < 1) )
		{$VARDB_pass = $line;   $VARDB_pass =~ s/.*=//gi;}
	if ( ($line =~ /^VARDB_port/) && ($CLIDB_port < 1) )
		{$VARDB_port = $line;   $VARDB_port =~ s/.*=//gi;}
	$i++;
	}

# Customized Variables
$server_ip = $VARserver_ip;		# Asterisk server IP

if (!$VARDB_port) {$VARDB_port='3306';}

use Time::HiRes ('gettimeofday','usleep','sleep');  # necessary to have perl sleep command of less than one second
use DBI;
use Net::Telnet ();
	  
$dbhA = DBI->connect("DBI:mysql:$VARDB_database:$VARDB_server:$VARDB_port", "$VARDB_user", "$VARDB_pass")
 or die "Couldn't connect to database: " . DBI->errstr;

### Grab Server values from the database
$stmtA = "SELECT telnet_host,telnet_port,ASTmgrUSERNAME,ASTmgrSECRET,ASTmgrUSERNAMEupdate,ASTmgrUSERNAMElisten,ASTmgrUSERNAMEsend,max_vicidial_trunks,answer_transfer_agent,local_gmt,ext_context,vicidial_recording_limit,asterisk_version,vd_server_logs FROM servers where server_ip = '$server_ip';";
if ($DB) {print "|$stmtA|\n";}
$sthA = $dbhA->prepare($stmtA) or die "preparing: ",$dbhA->errstr;
$sthA->execute or die "executing: $stmtA ", $dbhA->errstr;
$sthArows=$sthA->rows;
$rec_count=0;
if ($sthArows > 0)
    {
	@aryA = $sthA->fetchrow_array;
	$DBtelnet_host	=			$aryA[0];
	$DBtelnet_port	=			$aryA[1];
	$DBASTmgrUSERNAME	=		$aryA[2];
	$DBASTmgrSECRET	=			$aryA[3];
	$DBASTmgrUSERNAMEupdate	=	$aryA[4];
	$DBASTmgrUSERNAMElisten	=	$aryA[5];
	$DBASTmgrUSERNAMEsend	=	$aryA[6];
	$DBmax_vicidial_trunks	=	$aryA[7];
	$DBanswer_transfer_agent=	$aryA[8];
	$DBSERVER_GMT		=		$aryA[9];
	$DBext_context	=			$aryA[10];
	$vicidial_recording_limit = $aryA[11];
	$asterisk_version	=		$aryA[12];
	$DBvd_server_logs =			$aryA[13];
	if ($DBtelnet_host)				{$telnet_host = $DBtelnet_host;}
	if ($DBtelnet_port)				{$telnet_port = $DBtelnet_port;}
	if ($DBASTmgrUSERNAME)			{$ASTmgrUSERNAME = $DBASTmgrUSERNAME;}
	if ($DBASTmgrSECRET)			{$ASTmgrSECRET = $DBASTmgrSECRET;}
	if ($DBASTmgrUSERNAMEupdate)	{$ASTmgrUSERNAMEupdate = $DBASTmgrUSERNAMEupdate;}
	if ($DBASTmgrUSERNAMElisten)	{$ASTmgrUSERNAMElisten = $DBASTmgrUSERNAMElisten;}
	if ($DBASTmgrUSERNAMEsend)		{$ASTmgrUSERNAMEsend = $DBASTmgrUSERNAMEsend;}
	if ($DBmax_vicidial_trunks)		{$max_vicidial_trunks = $DBmax_vicidial_trunks;}
	if ($DBanswer_transfer_agent)	{$answer_transfer_agent = $DBanswer_transfer_agent;}
	if ($DBSERVER_GMT)				{$SERVER_GMT = $DBSERVER_GMT;}
	if ($DBext_context)				{$ext_context = $DBext_context;}
	if ($vicidial_recording_limit < 60) {$vicidial_recording_limit=60;}
	if ($DBvd_server_logs =~ /Y/)	{$SYSLOG = '1';}
	else {$SYSLOG = '0';}
	}
$sthA->finish(); 

# determine if we should use a \n\n at the end of the AMI commands
%ast_ver_str = parse_asterisk_version($asterisk_version);
$command_end = "\n\n";
if (( $ast_ver_str{major} = 1 ) && ($ast_ver_str{minor} >= 13)) { $command_end = '';}

if (!$telnet_port) {$telnet_port = '5038';}
if (length($ASTmgrUSERNAMEsend) > 3) {$telnet_login = $ASTmgrUSERNAMEsend;}
else {$telnet_login = $ASTmgrUSERNAME;}

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year = ($year + 1900);
$mon++;
if ($mon < 10) {$mon = "0$mon";}
if ($mday < 10) {$mday = "0$mday";}
if ($hour < 10) {$hour = "0$hour";}
if ($min < 10) {$min = "0$min";}
if ($sec < 10) {$sec = "0$sec";}

if (!$CONFLOGfile) {$CONFLOGfile = "$PATHlogs/3way_conf.$year-$mon-$mday";}

$event_string = "AST_conf_update_3way.pl script starting: $year-$mon-$mday $hour:$min:$sec";
 &event_logger;

$loop_counter=0;

while ($loops > $loop_counter)
	{
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year = ($year + 1900);
	$mon++;
	if ($mon < 10) {$mon = "0$mon";}
	if ($mday < 10) {$mday = "0$mday";}
	if ($hour < 10) {$hour = "0$hour";}
	if ($min < 10) {$min = "0$min";}
	if ($sec < 10) {$sec = "0$sec";}

	$now_date_epoch = time();
	$now_date = "$year-$mon-$mday $hour:$min:$sec";
	$current_hourmin = "$hour$min";

	##### Find date-time one hour in the past
	$secX = time();
	$TDtarget = ($secX - ($vicidial_recording_limit * 60));
	($Tsec,$Tmin,$Thour,$Tmday,$Tmon,$Tyear,$Twday,$Tyday,$Tisdst) = localtime($TDtarget);
	$Tyear = ($Tyear + 1900);
	$Tmon++;
	if ($Tmon < 10) {$Tmon = "0$Tmon";}
	if ($Tmday < 10) {$Tmday = "0$Tmday";}
	if ($Thour < 10) {$Thour = "0$Thour";}
	if ($Tmin < 10) {$Tmin = "0$Tmin";}
	if ($Tsec < 10) {$Tsec = "0$Tsec";}
	$TDSQLdate = "$Tyear-$Tmon-$Tmday $Thour:$Tmin:$Tsec";
	$TDrand = int( rand(99)) + 100;
	$TDnum = "$Tmon$Tmday$Thour$Tmin$Tsec$TDrand";
	$TDinc = 1;


	######################################################################
	##### CHECK vicidial_conferences TABLE #####
	######################################################################
	@PTextensions=@MT; @PT_conf_extens=@MT; @PTmessages=@MT; @PTold_messages=@MT; @NEW_messages=@MT; @OLD_messages=@MT;
	$stmtA = "SELECT extension,conf_exten from vicidial_conferences where server_ip='$server_ip' and leave_3way='1';";
	$sthA = $dbhA->prepare($stmtA) or die "preparing: ",$dbhA->errstr;
	$sthA->execute or die "executing: $stmtA ", $dbhA->errstr;
	$sthArows=$sthA->rows;
	$event_string = "$loop_counter|$sthArows|$stmtA";
	&event_logger;
	$rec_count=0;
	while ($sthArows > $rec_count)
		{
		@aryA = $sthA->fetchrow_array;
		$PTextensions[$rec_count] =		 $aryA[0];
		$PT_conf_extens[$rec_count] =	 $aryA[1];
		$event_string = "$PT_conf_extens[$rec_count]|$PTextensions[$rec_count]|";
		 &event_logger;
		$rec_count++;
		}
	$sthA->finish(); 

	if ($rec_count > 0)
		{
		$max_buffer = 4*1024*1024; # 4 meg buffer

		$t='';
		$telnet_log_file = '';
		### connect to asterisk manager through telnet
		if ($DBX)
			{
			$telnet_log_file = "$PATHlogs/AST_conf_telnet_log.$now_date_epoch";
			print "$telnet_log_file\n";
			$t = new Net::Telnet (
				Port => $telnet_port,
				Prompt => '/\r\n/',
				Output_record_separator => "\n\n",
				Max_buffer_length => $max_buffer,
				Telnetmode => 0,
				Dump_log => $telnet_log_file
			);
			}
		else
			{
			$t = new Net::Telnet (
				Port => $telnet_port,
				Prompt => '/\r\n/',
				Output_record_separator => "\n\n",
				Max_buffer_length => $max_buffer,
				Telnetmode => 0,
			);
			}

		if (length($ASTmgrUSERNAMEsend) > 3) {$telnet_login = $ASTmgrUSERNAMEsend;}
		else {$telnet_login = $ASTmgrUSERNAME;}
		$t->open("$telnet_host");
		$t->waitfor('/Asterisk Call Manager\//');

		# get the AMI version number
		$ami_version = $t->getline(Errmode => Return, Timeout => 1,);
		$ami_version =~ s/\n//gi;
		if ($DB) {print "----- AMI Version $ami_version -----\n";}

		$t->print("Action: Login\nUsername: $telnet_login\nSecret: $ASTmgrSECRET");
		$t->waitfor('/Authentication accepted/');	     # waitfor auth accepted

		$t->buffer_empty;

		$i=0;
		foreach(@PTextensions)
			{
			@list_channels=@MT;
			$t->buffer_empty;

			if ($ami_version =~ /^1\./i)
				{
				$COMMAND = "Action: Command\nCommand: Meetme list $PT_conf_extens[$i]\n\nAction: Ping$command_end";
				$event_string = "|$PT_conf_extens[$i]|$COMMAND|";
				&event_logger;
				%ast_ver_str = parse_asterisk_version($asterisk_version);
				if (( $ast_ver_str{major} = 1 ) && ($ast_ver_str{minor} < 6))
					{
					@list_channels = $t->cmd(String => "$COMMAND", Prompt => '/Response: Pong.*/');
					}
				else
					{
					@list_channels = $t->cmd(String => "$COMMAND", Prompt => '/Response: Success\nPing: Pong.*/');
					}
				}
			elsif ($ami_version =~ /^2\./i)
				{
				# get the current time
				( $now_sec, $now_micro_sec ) = gettimeofday();

				# figure out how many micro seconds since epoch
				$now_micro_epoch = $now_sec * 1000000;
				$now_micro_epoch = $now_micro_epoch + $now_micro_sec;

				$begin_micro_epoch = $now_micro_epoch;

				# create a new action id
				$action_id = "$now_sec.$now_micro_sec";

				$COMMAND = "Action: Command\nActionID:$action_id\nCommand: Meetme list $PT_conf_extens[$i]";
				$event_string = "|$PT_conf_extens[$i]|$COMMAND|";
				&event_logger;
				@list_channels = $t->cmd(String => "$COMMAND", Prompt => '/--END COMMAND--\n\n/');
				}
			elsif ($ami_version =~ /^5\./i)
				{
				# get the current time
				( $now_sec, $now_micro_sec ) = gettimeofday();

				# figure out how many micro seconds since epoch
				$now_micro_epoch = $now_sec * 1000000;
				$now_micro_epoch = $now_micro_epoch + $now_micro_sec;

				$begin_micro_epoch = $now_micro_epoch;

				# create a new action id
				$action_id = "$now_sec.$now_micro_sec";

				$COMMAND = "Action: Command\nActionID:$action_id\nCommand: Meetme list $PT_conf_extens[$i]";
				$event_string = "|$PT_conf_extens[$i]|$COMMAND|";
				&event_logger;
				@list_channels = $t->cmd(String => "$COMMAND", Prompt => '/\n\n/');
				}


			$j=0;
			$conf_empty[$i]=0;
			$conf_users[$i]='';
			foreach(@list_channels)
				{
				$event_string = "|$list_channels[$j]|";
				 &event_logger;
				### mark all empty conferences and conferences with only one channel as empty
				if ($list_channels[$j] =~ /No active conferences|No active MeetMe conferences|No such conference/i)
					{$conf_empty[$i]++;}
				if ($list_channels[$j] =~ /1 users in that conference/i)
					{$conf_empty[$i]++;}
				$j++;
				}

			$event_string = "Meetme list $PT_conf_extens[$i]-  Exten:|$PTextensions[$i]| Empty:|$conf_empty[$i]|";
			 &event_logger;
			if (!$conf_empty[$i])
				{
				$event_string = "CONFERENCE STILL HAS PARTICIPANTS, DOING NOTHING FOR THIS CONFERENCE";
				 &event_logger;
				if ($PTextensions[$i] =~ /Xtimeout\d$/i) 
					{
					$PTextensions[$i] =~ s/Xtimeout\d$//gi;
					$stmtA = "UPDATE vicidial_conferences set extension='$PTextensions[$i]' where server_ip='$server_ip' and conf_exten='$PT_conf_extens[$i]';";
					$affected_rows = $dbhA->do($stmtA); #  or die  "Couldn't execute query:|$stmtA|\n";
					$event_string = "|$affected_rows|$stmtA|";
					 &event_logger;
					}
				}
			else
				{
				$NEWexten[$i] = $PTextensions[$i];
				$leave_3waySQL='1';
				if ($PTextensions[$i] =~ /Xtimeout9$/i) {$NEWexten[$i] =~ s/Xtimeout9$/Xtimeout8/gi;}
				if ($PTextensions[$i] =~ /Xtimeout8$/i) {$NEWexten[$i] =~ s/Xtimeout8$/Xtimeout7/gi;}
				if ($PTextensions[$i] =~ /Xtimeout7$/i) {$NEWexten[$i] =~ s/Xtimeout7$/Xtimeout6/gi;}
				if ($PTextensions[$i] =~ /Xtimeout6$/i) {$NEWexten[$i] =~ s/Xtimeout6$/Xtimeout5/gi;}
				if ($PTextensions[$i] =~ /Xtimeout5$/i) {$NEWexten[$i] =~ s/Xtimeout5$/Xtimeout4/gi;}
				if ($PTextensions[$i] =~ /Xtimeout4$/i) {$NEWexten[$i] =~ s/Xtimeout4$/Xtimeout3/gi;}
				if ($PTextensions[$i] =~ /Xtimeout3$/i) {$NEWexten[$i] =~ s/Xtimeout3$/Xtimeout2/gi;}
				if ($PTextensions[$i] =~ /Xtimeout2$/i) {$NEWexten[$i] =~ s/Xtimeout2$/Xtimeout1/gi;}
				if ($PTextensions[$i] =~ /Xtimeout1$/i) {$NEWexten[$i] = ''; $leave_3waySQL='0';}
				if ( ($PTextensions[$i] !~ /Xtimeout\d$/i) and (length($PTextensions[$i])> 0) ) {$NEWexten[$i] .= 'Xtimeout2';}

				if ($NEWexten[$i] =~ /Xtimeout1$/i)
					{
					### Kick all participants if there are any left in the conference so it can be reused
					$local_DEF = 'Local/5555';
					$local_AMP = '@';
					$kick_local_channel = "$local_DEF$PT_conf_extens[$i]$local_AMP$ext_context";
					$padTDinc = sprintf("%03s", $TDinc);	while (length($padTDinc) > 3) {chop($padTDinc);}
					$queryCID = "ULGC$padTDinc$TDnum";

					$stmtA="INSERT INTO vicidial_manager values('','','$now_date','NEW','N','$server_ip','','Originate','$queryCID','Channel: $kick_local_channel','Context: $ext_context','Exten: 8300','Priority: 1','Callerid: $queryCID','','','','','');";
						$affected_rows = $dbhA->do($stmtA); #  or die  "Couldn't execute query:|$stmtA|\n";
					$event_string = "|$affected_rows|$stmtA|";
					 &event_logger;
					
					$TDinc++;
					}

				$stmtA = "UPDATE vicidial_conferences set extension='$NEWexten[$i]',leave_3way='$leave_3waySQL' where server_ip='$server_ip' and conf_exten='$PT_conf_extens[$i]';";
				$affected_rows = $dbhA->do($stmtA); #  or die  "Couldn't execute query:|$stmtA|\n";
				$event_string = "|$affected_rows|$stmtA|";
				 &event_logger;

				### sleep for 10 hundredths of a second
				usleep(1*100*1000);
				}

			$i++;
			}

		$t->buffer_empty;
		@hangup = $t->cmd(String => "Action: Logoff$command_end", Prompt => "/.*/"); 
		$t->buffer_empty;
		$t->waitfor(Match => '/Message:.*\n\n/', Timeout => 10);
		$ok = $t->close;

		if($DBX)
                	{
                	open (FILE, '<', "$telnet_log_file") or die "could not open the log file\n";
                	print <FILE>;
                	close (FILE);

			unlink($telnet_log_file) or die "Can't delete $telnet_log_file: $!\n";
                	}
		}

	### sleep for X delay seconds between runs
	sleep($CLIdelay);

	$loop_counter++;

	$timeclock_end_of_day_NOW=0;
	### Grab system_settings values from the database
	$stmtA = "SELECT count(*) from system_settings where timeclock_end_of_day LIKE \"%$current_hourmin%\";";
	$event_string = "|$stmtA|";
	 &event_logger;
	$sthA = $dbhA->prepare($stmtA) or die "preparing: ",$dbhA->errstr;
	$sthA->execute or die "executing: $stmtA ", $dbhA->errstr;
	$sthArows=$sthA->rows;
	if ($sthArows > 0)
		{
		@aryA = $sthA->fetchrow_array;
		$timeclock_end_of_day_NOW =	$aryA[0];
		}
	$sthA->finish();

	if ($timeclock_end_of_day_NOW > 0)
		{
		$event_string = "End of Day, shutting down this script in 10 seconds, script will resume in 60 seconds...";
		$event_string = "$event_string\n\n";
		 &event_logger;
		sleep(10);
		$loop_counter=9999999;
		}
	}


$dbhA->disconnect();

$event_string = "DONE... Exiting... Goodbye... See you later... \n";
 &event_logger;

exit;


# subroutine to parse the asterisk version
# and return a hash with the various part
sub parse_asterisk_version
{
	# grab the arguments
	my $ast_ver_str = $_[0];

	# get everything after the - and put it in $ast_ver_postfix
	my @hyphen_parts = split( /-/ , $ast_ver_str );

	my $ast_ver_postfix = $hyphen_parts[1];

	# now split everything before the - up by the .
	my @dot_parts = split( /\./ , $hyphen_parts[0] );

	my %ast_ver_hash;

	if ( $dot_parts[0] <= 1 )
		{
			%ast_ver_hash = (
				"major" => $dot_parts[0],
				"minor" => $dot_parts[1],
				"build" => $dot_parts[2],
				"revision" => $dot_parts[3],
				"postfix" => $ast_ver_postfix
			);
		}

	# digium dropped the 1 from asterisk 10 but we still need it
	if ( $dot_parts[0] > 1 )
		{
			%ast_ver_hash = (
				"major" => 1,
				"minor" => $dot_parts[0],
				"build" => $dot_parts[1],
				"revision" => $dot_parts[2],
				"postfix" => $ast_ver_postfix
			);
		}

	return ( %ast_ver_hash );
}

sub event_logger
	{
	if ($DB) {print "$now_date|$event_string|\n";}
	if ($SYSLOG)
		{
		### open the log file for writing ###
		open(Lout, ">>$CONFLOGfile")
				|| die "Can't open $CONFLOGfile: $!\n";
		print Lout "$now_date|$event_string|\n";
		close(Lout);
		}
	$event_string='';
	}
