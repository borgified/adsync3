#!/usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;

use Net::LDAPS;
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED );

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
		}
	}

	print Dumper($$employee_hashref{100648});

	#time to do comparisons and updates

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
				$adlib{lc($mail)}{'dn'}=$dn;
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
