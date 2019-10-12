#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use XML::LibXML;
use Encode;
use Image::ExifTool;
use File::Find::Rule;
use File::Basename;
use File::stat;

Getopt::Long::Configure qw(gnu_getopt);

my $man=0;
my $help=0;
my $verbose=0;
my $contacts_xml;
my $dry_run=0;
my $keep_time=0;
my $exclude_dir="\.picasaoriginals\$";
my $dir='.';
my %contacts;

sub vprint {
    print("$_[0]\n") if $verbose;
}

sub vvprint {
    print("$_[0]\n") if $verbose>1;
}

sub parse_options {
    GetOptions ('h|help' => \$help,
                'm|man' => \$man,
                'c|contacts-xml=s' => \$contacts_xml,
                'v|verbose+' => \$verbose,
                'n|dry-run' => \$dry_run,
                'k|keep-time' => \$keep_time,
                'x|exclude-dir=s' => \$exclude_dir)
        || pod2usage(-verbose => 1, -exitval=>2);

    pod2usage(1) if $help;
    pod2usage(-verbose => 2) if $man;

    if (not defined $contacts_xml) {
        print STDERR "Argument 'contacts-xml' is mandatory\n\n";
        pod2usage(-verbose => 1, -exitval=>2);
    }
    if (defined $ARGV[0]) {
        $dir = $ARGV[0];
    }
}

sub parse_contacts_xml {
    vprint "Reading contacts file $contacts_xml";
    if (! -e "$contacts_xml") {
        die "Missing $contacts_xml file";
    }

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
    if ($id eq 'ffffffffffffffff') {
        return 'UNKNOWN';
    } elsif (defined $local_name) {
        return $local_name;
    } else {
        return $contacts{$id};
    }
}

sub create_acdsee_xml {
    my @names = @_;
    my $doc = XML::LibXML::Document->new('1.0', 'utf-8');
    my $root = $doc->createElement("Categories");
    my $category = $doc->createElement("Category");
    $category->setAttribute("Assigned" => "0");
    $category->appendTextNode("People");
    $root->appendChild($category);
    foreach my $name (@names) {
        my $sub_category = $doc->createElement("Category");
        $sub_category->setAttribute("Assigned" => "1");
        $sub_category->appendTextNode($name);
        $category->appendChild($sub_category);
    }
    $doc->setDocumentElement($root);
    return $root->toString();
}

sub add_face_info {
    my ($dir_name, $file, @faces) = @_;
    my $full_name = "$dir_name/$file";
    my $success = 1;
    my $extra_info = '';
    if (! -e "$full_name") {
        $success = 0;
        $extra_info =  " - missing file";
    }

    my $face_num = scalar @faces;
    vprint "Adding $face_num faces to $full_name $extra_info";
    if ($dry_run || !$success) {
        return $success * $face_num;
    }
    my $et = Image::ExifTool->new;
    my @names;
    my @people_slash;
    my @people_pipe;
    my @region_info_mp;
    my @region_info;
    for (my $i=0; $i<$face_num; ++$i) {
        my $name = $faces[$i]{name};
        my $left = $faces[$i]{left};
        my $top = $faces[$i]{top};
        my $right = $faces[$i]{right};
        my $bottom = $faces[$i]{bottom};
        my $width = $right - $left;
        my $height = $bottom - $top;
        my $middle_x = $left + $width / 2;
        my $middle_y = $top + $height / 2;
        push @names, "$name";
        push @people_slash, "People/$name";
        push @people_pipe, "People|$name";
        push @region_info_mp, {(Rectangle=>"$left,$top,$width,$height",
                                PersonDisplayName => "$name")};
        push @region_info, {(Name=>"$name",
                             Type=>"Face",
                             Area=>{(Unit=>"Normalized",X=>"$middle_x",Y=>"$middle_y",W=>"$width",H=>"$height")})};
    }
    $et->SetNewValue(LastKeywordXMP => \@people_slash);
    $et->SetNewValue(TagsList => \@people_slash);
    $et->SetNewValue(hierarchicalSubject => \@people_pipe);
    $et->SetNewValue('XMP:CatalogSets' => \@people_pipe);
    $et->SetNewValue(subject => \@names);
    $et->SetNewValue(categories => create_acdsee_xml(@names));
    $et->SetNewValue(Keywords => \@names, DelValue => 1);
    $et->SetNewValue(Keywords => \@names, AddValue => 2);

    my %region_info_mps = ('Regions' => \@region_info_mp);
    $et->SetNewValue(RegionInfoMP => \%region_info_mps);
    my %region_infos = ('RegionList' => \@region_info);
    $et->SetNewValue(RegionInfo => \%region_infos);

    my $pre_atime = stat($full_name)->atime;
    my $pre_mtime = stat($full_name)->mtime;
    $et->WriteInfo($full_name);
    if ($keep_time) {
        utime($pre_atime, $pre_mtime, $full_name);
    }
    return $success * $face_num;
}

sub process_picasa_ini {
    my ($picasa_ini) = @_;
    my $dir_name = dirname($picasa_ini);
    my $in_contacts = '';
    my $file_name;
    my %local_contacts;
    my $faces_found = 0;
    my $faces_written = 0;
    my $faces_missing = 0;
    my @names;

    if ($dir_name =~ /$exclude_dir/) {
        vprint "Excluding $dir_name";
        return (0,0,0);
    } else {
        vprint "Processing $picasa_ini";
    }
    open (my $fh_picasa_ini, '<', $picasa_ini) || die "Unable to open $picasa_ini file";

    while (<$fh_picasa_ini>) {
        if ($_ =~ /\[Contacts2\]/) {
            $in_contacts = 1;
        } elsif ($in_contacts && $_ =~ /(.*)=([^;]*);/) {
            vvprint "  Found local contact in file $picasa_ini: $1 $2";
            $local_contacts{$1} = $2;
        } elsif ($_ =~ /\[(.*)\]/) {
            if (scalar @names>0) {
                $faces_written += add_face_info($dir_name, $file_name, @names);
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
                my $contact_id = $5;
                my $name = contact_name_by_id ($contact_id, %local_contacts);
                if (!defined $name) {
                    vvprint "  Missing contact info $contact_id";
                    ++$faces_missing;
                } else {
                    my %face = (name => $name, left => $left, top => $top, right => $right, bottom => $bottom);
                    vvprint ("  Found face for $name in $file_name");
                    push @names, { %face };
                    ++$faces_found;
                }
                $faces_str = $6;
            }
        }
    }
    close ($fh_picasa_ini);
    if (scalar @names>0) {
        $faces_written += add_face_info($dir_name, $file_name, @names);
    }
    vprint "Found $faces_found faces in $picasa_ini, written $faces_written faces";
    if ($faces_missing>0) {
        vprint "Fount $faces_missing faces with missing contact info";
    }
    return ($faces_found, $faces_written, $faces_missing);
}

sub process_dir {
    my ($dir) = @_;
    vprint "Starting processing $dir";
    if (! -e "$dir" || ! -d "$dir") {
        die "Cannot find directory $dir";
    }

    my @files = File::Find::Rule->file()
        ->name( '.picasa.ini' )
        ->in( $dir );
    my $total_faces_found = 0;
    my $total_faces_written = 0;
    my $total_faces_missing = 0;
    foreach my $file (@files) {
        my ($ff, $fw, $fm) = process_picasa_ini($file);
        $total_faces_found += $ff;
        $total_faces_written += $fw;
        $total_faces_missing += $fm;
    }
    print "Total: Found $total_faces_found faces ($total_faces_missing with mising contact info), written $total_faces_written faces\n";
}

parse_options();
parse_contacts_xml();
process_dir($dir);
__END__

=head1 NAME

picasa2xmp - converts picasa face / contact information to xmp

=head1 SYNOPSIS

picasa2xmp.pl [options] --contacts-xml picasa_contacts.xml DIRECTORY

=head1 OPTIONS

=over 4

=item B<DIRECTORY>

    Specifies the directory which contains the image files. If not specified the script works on the current directory.

=item B<-x|--exclude-dir>

    Specifies the directories (using regular expression) which should be excluded. Default value: "\.picasaoriginals$".

=item B<-c|--contacts-xml>

    Specifies the picasa contacts xml file. This is a mandatory option.

=item B<-v|--verbose>

    Turns on verbose mode, the program prints out more information. Can be specified multiple times to increase verbosity.

=item B<-n|--dry-run>

    Perform a trial run with no changes. Useful for testing.

=item B<-k|--keep-time>

    Keep the original dates of the files.

=item B<-h|--help>

    Prints out the help page.

=item B<-m|--man>

    Prints out the man page.

=back

=head1 DESCRIPTION

    picas2xmp reads the picasa face / contact information from .picasa.ini
    and contact.xml files and converts it to xmp tags.

=head1 AUTHOR

    Andras Salamon <andras.salamon@melda.info>

=cut
