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

	print Dumper($$employee_hashref{100251});

	#gather dn data
	my $dn = &dn_lookup;

	#store dn information in $employee_hashref (this is for manager lookup, used later)
	foreach my $key (keys(%$employee_hashref)){

		if(exists($$dn{$$employee_hashref{$key}->{'Work Email'}})){
			$$employee_hashref{$key}->{'dn'}=$$dn{$$employee_hashref{$key}->{'Work Email'}};
		}else{
			warn "couldn't look up $$employee_hashref{$key}->{'Work Email'}\n";
		}
	}

	print Dumper($$employee_hashref{100251});

	#time to do comparisons and updates

}
&main;

sub dn_lookup{
	#output: \%hash{mail}=dn of every account in AD

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
		filter   => "(mail=*)",
		control  => [ $page ],
	);

	my $cookie;
	my %dnlib;

	while(1){
		my $mesg = $ldap->search( @args );
		die "LDAP error: server says ",$mesg->error,"\n" if $mesg->code;
		$mesg->code  and last;

		foreach ($mesg->entries) {
			my $dn = defined($_->get_value('distinguishedName')) ? $_->get_value('distinguishedName') : "none";
			my $mail = defined($_->get_value('mail')) ? $_->get_value('mail') : "none";

			#print "$mail $dn\n";
			if(!exists($dnlib{$mail})){
				$dnlib{lc($mail)}=$dn;
			}else{
				warn "warning: already encountered $mail (can be ignored if not an actual user account)
				\texisting value: $dnlib{$mail}
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

	return \%dnlib;
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
