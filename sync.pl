#!/usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;

use Net::LDAPS;
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED );
use Locale::Country;

use Text::CSV;

sub main{

	my $itrpt = shift @ARGV or die "no input file given\n";

	#populate $employee_hashref with ITRPT data
	my $employee_hashref = &parseITRPT($itrpt);

	#picked 100648 because this employee's dn has special accent mark, make sure script handles utf8 properly
	print Dumper($$employee_hashref{100648});

	#gather ad data from AD
	my $ad = &ad_lookup;

	#store dn information into $employee_hashref (this is for manager lookup, used later)
	foreach my $key (keys(%$employee_hashref)){

		if(exists($$ad{$$employee_hashref{$key}->{'Work Email'}}{'dn'})){
			$$employee_hashref{$key}->{'dn'}=$$ad{$$employee_hashref{$key}->{'Work Email'}}{'dn'};
		}else{
			warn "couldn't look up $$employee_hashref{$key}->{'Work Email'}\n";
			warn "check to see if this account is disabled in AD\n";
			<>;
		}
	}

	print Dumper($$employee_hashref{100648});

	print Dumper($$ad{$$employee_hashref{100648}->{'Work Email'}});

	#time to do comparisons and updates

	#mappings CSV:AD
	#
	#First Name: givenName = ('First Name' eq 'Preferred Name') ? 'First Name' : 'Preferred Name'  
	#Preferred Name: 
	#Last Name: sn
	#Employee Id: employeeID
	#Job title: title
	#Business Unit: company
	#Home Department: department.description
	#Location: c-st-physicalDeliveryOfficeName
	#Work Phone: telephoneNumber
	#Work Fax: facsimileTelephoneNumber
	#Work Email: mail
	#Manager ID: none but will be linked to manager
	#Mngr. FName: ignored
	#Mngr. MName: ignored
	#Mngr. LName: ignored

	my $count=1;
	my $total=scalar keys(%$employee_hashref);

	foreach my $eid (sort keys(%$employee_hashref)){

		print "processing $$employee_hashref{$eid}->{'Work Email'} ($count/$total)\n";
		$count++;

		my $itrpt_fn = $$employee_hashref{$eid}->{'First Name'};
		my $itrpt_pn = $$employee_hashref{$eid}->{'Preferred Name'};
		my $ad_gn = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'givenName'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'givenName'} : "givenName not found in AD";
		my $ad_dn = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'displayname'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'displayname'} : "displayName not found in AD";

		#skip this user if hes not even able to be found in AD (this account is probably disabled)
		if($ad_gn eq 'givenName not found in AD'){
			print "skipping $$employee_hashref{$eid}->{'Work Email'}\nreason: $ad_gn\n";
			print "==================================\n";	
			<>;
			next;
		}

		######NAME

		#for most people their first name and pref name are the same
		if($itrpt_fn eq $itrpt_pn){
			print "fn and pn same\n";
			#let's check to make sure that their givenname in ad matches as well
			if($itrpt_fn eq $ad_gn){
				print "fn and gn same\n";
				#all checks out, no changes needed
			}else{
				#we need to make them the same:
				print "ITRPT(First Name): $itrpt_fn\n";
				print "AD(givenName): $ad_gn\n";
				print "AD(displayName): $ad_dn\n";
				print "mismatch detected: you must make this change manually in AD\n";
				<>;
			}

		}else{
			print "fn and pn differ\n";
			#there are a handful of people who want to use an alternate name (pref name)

			#see if they are already using the alternate name in ad (eg. itrpt_pref name = ad_displayname)
			#however displayname contains their entire name (first middle last), so we have to pop out the first name
			#to make the comparison with itrpt's pref name
			my @ad_dn = split (/ /,$ad_dn);
			my $ad_dn_fn = shift(@ad_dn);
			if($itrpt_pn eq $ad_dn_fn){
				#good, this user is already using preferred name in their displayname
				print "pn and first portion in display name are same: $itrpt_pn : $ad_dn\n";
			}else{
				#we must make changes to their displayname so that it uses the pref name
				print "ITRPT(Pref Name): $itrpt_pn\n";
				print "AD(givenName): $ad_gn\n";
				print "AD(displayName): $ad_dn\n";
				print "mismatch detected: you must make this change manually in AD\n";
				<>;
			}

		}

		######JOB TITLE

		my $itrpt_jt = $$employee_hashref{$eid}->{'Job title'};
		my $ad_title = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'title'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'title'} : "title not found in AD";

		if($itrpt_jt ne $ad_title){
			print "ITRPT(Job Title): $itrpt_jt\n";
			print "AD(title): $ad_title\n";
			print "mismatch detected: you must make this change manually in AD\n";
			<>;
		}

		######Business Unit: company

		my $itrpt_bu = $$employee_hashref{$eid}->{'Business Unit'};
		my $ad_comp = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'company'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'company'} : "company not found in AD";


		if($itrpt_bu ne $ad_comp){
			print "ITRPT(Business Unit): $itrpt_bu\n";
			print "AD(company): $ad_comp (should be $itrpt_bu)\n";
			print "mismatch detected: you must make this change manually in AD\n";
			<>;
		}


		######Home Department: department.description


		my $itrpt_hd = $$employee_hashref{$eid}->{'Home Department'};
		my $ad_dept = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'dept'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'dept'} : "dept not found in AD";
		my $ad_desc = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'desc'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'desc'} : "desc not found in AD";

		#the itrpt 'Home Department' field is made up of two components. 1. dept and 2. desc. these two components are joined by a dot.
		#we'll split up the 'Home Department' field and check that the corresponding entries in AD match

		my $number_of_dots = split(/\./,$itrpt_hd);

		my $itrpt_hd_dept;
		my $itrpt_hd_desc;
		if($number_of_dots == 2){
			$itrpt_hd_dept = $itrpt_hd;
			$itrpt_hd_desc = "none";
		}elsif($number_of_dots == 3){
			$itrpt_hd=~/(.*\..*)\.(.*)/;
			$itrpt_hd_dept = $1;
			$itrpt_hd_desc = $2;
		}else{
			die "unrecognized Home Department format: $itrpt_hd\n";
		}


		if($itrpt_hd_dept ne $ad_dept){
			print "ITRPT(Home Department (dept)): $itrpt_hd_dept\n";
			print "AD(dept): $ad_dept\n";
			print "mismatch detected: you must make this change manually in AD\n";
			<>;
		}

		if($itrpt_hd_desc ne $ad_desc){
			print "ITRPT(Home Department (desc)): $itrpt_hd_desc\n";
			print "AD(desc): $ad_desc\n";
			print "mismatch detected: you must make this change manually in AD\n";
			<>;
		}


		#####Location: c-st-physicalDeliveryOfficeName
		#
		my $itrpt_loc = $$employee_hashref{$eid}->{'Location'};
		my $ad_l = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'l'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'l'} : "l not found in AD";
		my $ad_co = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'co'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'co'} : "co not found in AD";
		my $ad_st = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'st'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'st'} : "st not found in AD";
		my $ad_pdon = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'physicalDeliveryOfficeName'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'physicalDeliveryOfficeName'} : "physicalDeliveryOfficeName not found in AD";


		#Location field comes in several formats depending on whether it contains 1 or 2 dashes. Here are all the different variations:
		#Germany-Hamburg
		#India-Remote
		#UK-Slough
		#US-Texas-Austin
		#US-Ohio-Remote
		#US-South Carolina
		#US-New Mexico-Remote
		#US-California-Redwood City (HQ)

		#the data in location field maps to 4 entries in AD: co (country), st (state), l (city), physicalDeliveryOfficeName (office)
		#following the prev example, here are the mappings:
		#
		#Germany-Hamburg										co=Germany, st=none, l=Hamburg, pdon=Hamburg
		#India-Remote												co=India, st=none, l=none, pdon=Remote 
		#UK-Slough													co=United Kingdom, st=none, l=Slough, pdon=Slough
		#US-Texas-Austin										co=United States, st=Texas, l=Austin, pdon=Austin
		#US-Ohio-Remote											co=United States, st=Ohio, l=none, pdon=Remote
		#US-South Carolina									co=United States, st=South Carolina, l=none, pdon=South Carolina
		#US-New Mexico-Remote								co=United States, st=New Mexico, l=none, pdon=Remote
		#US-California-Redwood City (HQ)		co=United States, st=California, l=Redwood City, pdon=Redwood City (HQ)

		#strat:
		#how many dashes? 1 or 2
		#
		#1 dash:
		#is first chunk 2 letters long (in country code)? if so, spell it out
		#is first chunk 'US'? if so, st=second chunk, l=none, pdon=second chunk
		#is second chunk 'Remote'? if so, st=l=none and pdon=Remote
		#
		#2 dashes:
		#is first chunk 2 letters long (in country code)? if so, spell it out
		#is third chunk 'Remote'? if so, l=none, pdon=Remote
		#is third chunk 'Redwood City (HQ)'? if so , l=Redwood City, pdon=Redwood City (HQ)

		#print "ITRPT(Location): $itrpt_loc\n";
		#print "AD(co): $ad_co\n";
		#print "AD(st): $ad_st\n";
		#print "AD(l): $ad_l\n";
		#print "AD(physicalDeliveryOfficeName): $ad_pdon\n";
		#<>;

		my @location = split (/-/,$itrpt_loc);

		#if ITRPT(Location) ends with Remote, pdon should be set to Remote
		if($location[-1] eq 'Remote'){
			if($ad_pdon ne 'Remote'){
				print "AD(physicalDeliveryOfficeName): $ad_pdon (should be 'Remote')\n";
			}
		}

		#the first chunk is always the country
		my $itrpt_loc_country;

		if($location[0] eq 'UK'){
			$itrpt_loc_country = code2country('GB');
		}elsif($location[0] =~/\b\w\w\b/){ 
			$itrpt_loc_country = code2country($location[0]);
		}else{
			$itrpt_loc_country = $location[0];
		}

		if($itrpt_loc_country eq $ad_co){
			#countries match
		}else{
			print "AD(co): $ad_co (should be $itrpt_loc_country)\n";
			<>;
		}	

		#if the first chunk is US, second chunk is a state unless it is Remote
		if(($location[0] eq 'US')&&($location[1] ne 'Remote')){
			if($location[1] eq $ad_st){
				#states should match
			}else{
				print "AD(st): $ad_st (should be $location[1])\n";
				<>;
			}
		}

		#if the last item is Redwood City (HQ), city should be just 'Redwood City'
		if($location[-1] eq 'Redwood City (HQ)'){
			if($ad_l ne 'Redwood City'){
				print "AD(l): $ad_l (should be 'Redwood City')\n";
				<>;
			}
			#if there are 3 items in @location and last item isnt Remote, then last item is a city
		}elsif((scalar(@location) == 3) && ($location[-1] ne 'Remote')){
			if($location[-1] ne $ad_l){
				print "AD(l): $ad_l (should be $location[-1])\n";
				<>;
			}   
		}


		#if there are two items in @location and first item isnt 'US', then 2nd item is a city unless it is 'Remote'
		if(((scalar(@location)) == 2) && ($location[0] ne 'US') && ($location[1] ne 'Remote')){
			if($location[1] ne $ad_l){
				print "AD(l): $ad_l (should be $location[1])\n";
				<>;
			}
		}


	#####Manager ID

		my $itrpt_mid = $$employee_hashref{$eid}->{'Manager ID'};
		my $ad_manager = $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'manager'} ? $$ad{$$employee_hashref{$eid}->{'Work Email'}}->{'manager'} : "manager not found in AD";

		#print "ITRPT(MID): $itrpt_mid\n";
		#print "AD(manager): $ad_manager\n";
		#<>;

		#find out which email $itrpt_mid corresponds to
		my $itrpt_memail = $$employee_hashref{$itrpt_mid}->{'Work Email'};

		#hack to skip the CEO, cuz he doesnt have a manager
		if(!defined($itrpt_memail) && $eid == 100177){
			next;
		}


		#derive the dn of manager email (mid) from the step above.	
		my $itrpt_manager_dn = $$ad{$itrpt_memail}->{'dn'};

		if(!defined($itrpt_manager_dn)){
			print "could not find the manager. verify that $itrpt_memail is still an active employee.\n";
			print "AD(manager): $ad_manager (currently set)\n";
			<>;
			next;
		}
	
		#we now compare dn's. one is obtained from AD because every employee has a defined manager, expressed in dn.
		#the other dn is figured out by using the manager id field in the ITRPT report, working out the email that the id corresponds to
		#then figuring out the dn that goes with that particular email.
		
		if($itrpt_manager_dn ne $ad_manager){
			print "AD(manager): $ad_manager (should be $itrpt_manager_dn)\n";
			<>;
		}




		print "==================================\n";	
	}
}
&main;

sub ad_lookup{
	#output: \%hash{mail}{<category>}=dn of every account in AD (based on filter)

	my %config = do '/secret/actian.config';

	my($ldap) = Net::LDAPS->new($config{'host'}) or die "Can't bind to ldap: $!\n";

	$ldap->bind(
		dn  => "$config{'username'}",
		password => "$config{'password'}",
	);  

	my $page = Net::LDAP::Control::Paged->new( size => 100 );

	my @args = ( 
		base     => $config{'base'},
		scope    => "subtree",
		filter   => "(&(samAccountType=805306368)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(mail=*))",
		control  => [ $page ],
	);

	my $cookie;
	my %adlib;

	while(1){
		my $mesg = $ldap->search( @args );
		die "LDAP error: server says ",$mesg->error,"\n" if $mesg->code;
		$mesg->code  and last;

		foreach ($mesg->entries) {
			my $dn = defined($_->get_value('distinguishedName')) ? $_->get_value('distinguishedName') : "none";
			my $mail = defined($_->get_value('mail')) ? $_->get_value('mail') : "none";


			my $title = defined($_->get_value('title')) ? $_->get_value('title') : "none";
			my $dept = defined($_->get_value('department')) ? $_->get_value('department') : "none";
			my $desc = defined($_->get_value('description')) ? $_->get_value('description') : "none";
			my $sam = defined($_->get_value('samaccountname')) ? $_->get_value('samaccountname') : "none";
			my $givenName = defined($_->get_value('givenName')) ? $_->get_value('givenName') : "none";
			my $sn = defined($_->get_value('sn')) ? $_->get_value('sn') : "none";
			my $displayname = defined($_->get_value('displayname')) ? $_->get_value('displayname') : "none";
			my $company = defined($_->get_value('company')) ? $_->get_value('company') : "none";
			my $c = defined($_->get_value('c')) ? $_->get_value('c') : "none";
			my $co = defined($_->get_value('co')) ? $_->get_value('co') : "none";
			my $st = defined($_->get_value('st')) ? $_->get_value('st') : "none";
			my $physicalDeliveryOfficeName = defined($_->get_value('physicalDeliveryOfficeName')) ? $_->get_value('physicalDeliveryOfficeName') : "none";
			my $telephoneNumber = defined($_->get_value('telephoneNumber')) ? $_->get_value('telephoneNumber') : "none";
			my $facsimileTelephoneNumber = defined($_->get_value('facsimileTelephoneNumber')) ? $_->get_value('facsimileTelephoneNumber') : "none";
			my $manager = defined($_->get_value('manager')) ? $_->get_value('manager') : "none";
			my $l = defined($_->get_value('l')) ? $_->get_value('l') : "none";
			my $upn = defined($_->get_value('userprincipalname')) ? $_->get_value('userprincipalname') : "none";
			my $name = defined($_->get_value('name')) ? $_->get_value('name') : "none";




			#print "$mail $dn\n";
			if(!exists($adlib{$mail}{'dn'})){
				$mail=lc($mail);

				$adlib{$mail}{'dn'}=$dn;
				$adlib{$mail}{'title'}=$title;
				$adlib{$mail}{'dept'}=$dept;
				$adlib{$mail}{'desc'}=$desc;
				$adlib{$mail}{'sam'}=$sam;
				$adlib{$mail}{'givenName'}=$givenName;
				$adlib{$mail}{'sn'}=$sn;
				$adlib{$mail}{'displayname'}=$displayname;
				$adlib{$mail}{'company'}=$company;
				$adlib{$mail}{'c'}=$c;
				$adlib{$mail}{'co'}=$co;
				$adlib{$mail}{'st'}=$st;
				$adlib{$mail}{'physicalDeliveryOfficeName'}=$physicalDeliveryOfficeName;
				$adlib{$mail}{'telephoneNumber'}=$telephoneNumber;
				$adlib{$mail}{'facsimileTelephoneNumber'}=$facsimileTelephoneNumber;
				$adlib{$mail}{'manager'}=$manager;
				$adlib{$mail}{'l'}=$l;
				$adlib{$mail}{'upn'}=$upn;
				$adlib{$mail}{'name'}=$name;
			}else{
				warn "warning: already encountered $mail (can be ignored if not an actual user account)
				\texisting value: $adlib{$mail}{'dn'}
				\tnew value     : $dn\n\n";
			}
		}
		# Get cookie from paged control
		my($resp)  = $mesg->control( LDAP_CONTROL_PAGED )  or last;
		$cookie    = $resp->cookie;

		# Only continue if cookie is nonempty (= we're not done)
		last  if (!defined($cookie) || !length($cookie));

		# Set cookie in paged control
		$page->cookie($cookie);

	}
	if (defined($cookie) && (length($cookie))) {
		# We had an abnormal exit, so let the server know we do not want any more
		$page->cookie($cookie);
		$page->size(0);
		$ldap->search( @args );
	}

	return \%adlib;
}

sub parseITRPT{
#input: ITRPT.csv
#output: \%employee
	my $file = shift;


	open(my $data, '<:encoding(utf8)', $file) or die "couldnt open file $!\n";

	my $csv = Text::CSV->new ({
			binary    => 1,
			auto_diag => 1,
			sep_char  => ',',
		}); 



	my %employees;
	my @header;


	while(my $fields = $csv->getline($data)){
		#detect if the first field starts with 'Employee Name' if so, then this is
		#our header we'll use it as the key for our hash.

		my $x=0;

		if(${$fields}[0] eq 'First Name'){
			@header=@{$fields};
			next;
		}else{

			foreach my $field (@{$fields}){
				#${$fields}[3] is eeid
				if($header[$x] eq 'Work Email'){
					$employees{"${$fields}[3]"}{"$header[$x]"}=lc($field);
				}else{
					$employees{"${$fields}[3]"}{"$header[$x]"}="$field";
				}
				$x++;
			}

		}
	}

	unless($csv->eof){
		$csv->error_diag();
	}

	close($data);

	return \%employees;

}

sub slurp {
	my $file = shift;
	open my $fh, '<', $file or die;
	local $/ = undef;
	my $cont = <$fh>;
	close $fh;
	return $cont;
}



#notes
#
#ITRPT 
#has email (but not 100% reliable)
#has EID
#has data that is used to overwrite AD attributes like title, manager, etc
#
#AD
#has email (official email)
#
#
#before anything else, we need to establish a relationship between dn, email,
#and name so that the manager field can be filled in (it accepts dn only)
#
#email and name should come from ITRPT and dn can be obtained from AD
#store these 3 items on the same row in a database so it can be searched later.
#
#
#main program loop
#
#parse a line of ITRPT
#find the email
#look for the account in AD based on email
#compare attributes in ITRPT vs ones in AD, if different, ITRPT overwrites AD
#
#if email isnt found, this is an error. possible causes:
#email account not created
#typo in AD
#typo in ITRPT
#
#
#added features
#
#some people have preferred names, use preferred names when updating AD
#
#create an output file of emails of accounts successfully processed in
#case the script needs to be run again after an interruption and can just
#pick up from where it left off.
