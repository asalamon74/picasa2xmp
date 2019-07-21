#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use XML::LibXML;
use Encode;
use Image::ExifTool;

my $verbose;
my $contacts_xml;
my $dir='.';
my %contacts;

sub vprint {
    print("$_[0]\n") if $verbose;
}

sub vvprint {
    print("$_[0]\n") if $verbose>1;
}

sub parse_options {
    GetOptions ("contacts_xml=s" => \$contacts_xml,
                'verbose+' => \$verbose)
        || pod2usage(2);

    if (not defined $contacts_xml) {
        print STDERR "Argument 'contacts_xml' is mandatory\n\n";
        pod2usage(2);
    }
    if (defined $ARGV[0]) {
        $dir = $ARGV[0];
    }
}

sub parse_contacts_xml {
    my $dom = XML::LibXML->load_xml(location => $contacts_xml);
    my @contacts_array = $dom->findnodes('//contact');

    vprint "Found " . scalar @contacts_array . " contacts";

    vvprint "Contacts in contacts.ini:";
    foreach my $contact (@contacts_array) {
        my $id = $contact->findvalue('./@id');
        my $name = Encode::encode("UTF-8", $contact->findvalue('./@name'));
        vvprint "  $id: $name";
        $contacts{$id} = $name;
    }
}

sub contact_name_by_id {
    my ($id, %local_contacts) = @_;
    my $local_name = $local_contacts{$id};
    if (defined $local_name) {
        return $local_name;
    } else {
        return $contacts{$id};
    }
}

sub add_face_info {
    my ($file, @names) = @_;
    vprint "Adding " . (scalar @names) . " faces to $file";
    my $et = new Image::ExifTool;
    my @people_slash;
    foreach my $name (@names) {
        push @people_slash, "People/$name";
    }
    $et->SetNewValue(LastKeywordXMP => \@people_slash);
    $et->WriteInfo($file);
}

sub read_picasa_ini {
    my $picasa_ini = "$_[0]/.picasa.ini";
    my $in_contacts = '';
    my $file_name;
    my %local_contacts;
    my $faces = 0;
    my @names;
    vprint "Processing $picasa_ini";
    open (my $fh_picasa_ini, '<', $picasa_ini) || die "Unable to open $picasa_ini file";

    while (<$fh_picasa_ini>) {
        if ($_ =~ /\[Contacts2\]/) {
            $in_contacts = 1;
        } elsif ($in_contacts && $_ =~ /(.*)=([^;]*);/) {
            vvprint "  Found local contact in file $picasa_ini: $1 $2";
            $local_contacts{$1} = $2;
        } elsif ($_ =~ /\[(.*)\]/) {
            if (scalar @names>0) {
                add_face_info($file_name, @names);
                @names = ();
            }
            $in_contacts = 0;
            $file_name = $1;
        } elsif ($_ =~ /faces=(.*)/) {
            my $faces_str = $1;
            while ($faces_str =~ /rect64\((.{4})(.{4})(.{4})(.{4})\),([[:xdigit:]]*)(.*)/) {
                my $left = hex ($1) / (1<<16);
                my $top = hex ($2) / (1<<16);
                my $right = hex ($3) / (1<<16);
                my $bottom = hex ($4) / (1<<16);
                my $name = contact_name_by_id ($5, %local_contacts);
                vvprint ("  Found face for $name in $file_name");
                push @names, $name;
                ++$faces;
                $faces_str = $6;
            }
        } else {
#            print "$_\n";
        }
    }
    if (scalar @names>0) {
        add_face_info($file_name, @names);
    }
    close ($fh_picasa_ini);
    vprint "Found $faces faces in $picasa_ini";

#    foreach my $id (keys %local_contacts) {
#        vprint "zzz $id " . $local_contacts{$id};
#    }
}


parse_options();
vprint "Starting... $dir";
parse_contacts_xml();
read_picasa_ini $dir;
__END__

=head1 NAME

picasa2xmp - converts picasa contacts information to xmp

=head1 SYNOPSIS

picasa2xmp.pl [options] --contacts_xml picasa_contacts.xml DIRECTORY

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
