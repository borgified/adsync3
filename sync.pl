#!/usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;

sub main{

	my $itrpt = shift @ARGV or die "no input file given\n";

	&parseITRPT($itrpt);

}
&main;

sub parseITRPT{
	my $file = shift;
	my $data = slurp($file);

	#first line is the header
	my @lines = split(/\n/,$data);
	my $header = shift(@lines);

	my @keys = split(/,/,$header);

	my %employee;

	foreach my $line (@lines){
		my @values = split(/,/,$line);
		for(my $x=0;$x < $#keys;$x++){
			$employee{$values[3]}{$keys[$x]}=$values[$x];
		}
	}

	print Dumper($employee{100251});
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
