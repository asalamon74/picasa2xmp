#!/usr/bin/perl -w
use strict;
use Getopt::Long;
use Pod::Usage;

my $verbose = '';
my $contacts_xml;

sub vprint {
    print("$_[0]\n") if $verbose;
}

sub parse_options {
    GetOptions ("contacts_xml=s" => \$contacts_xml,
                'verbose' => \$verbose)
        || pod2usage(2);

    if (not defined $contacts_xml) {
        print STDERR "Argument 'contacts_xml' is mandatory\n\n";
        pod2usage(2);
    }
}

parse_options();
vprint "Starting...";

__END__

=head1 NAME

picasa2xmp - converts picasa contacts information to xmp

=head1 SYNOPSIS

picasa2xmp.pl [options] --contacts_xml picasa_contacts.xml

Options:

    -verbose    turn on verbose mode

=head1 OPTIONS

=over 4

=item B<-verbose>

    Turns on verbose mode, the program prints out more information.

=back

=head1 DESCRIPTION

    picas2xmp reads the picasa contacts information and converts it to xmp tags.

=cut
