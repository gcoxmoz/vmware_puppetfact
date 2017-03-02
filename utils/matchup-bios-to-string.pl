#!/usr/bin/perl -w
#
# gcox@mozilla
#
use strict;
use warnings;
use Getopt::Long;
use File::Find;
use JSON;

my $build_num_json_file = '../build_numbers/esxi_build_numbers.json';
my $dmidecode_dir       = '../dmidecode';

# Show minor (6.0u2) or major (6.0) versions?
my $minor_version = 0;
# Sometimes, multiple releases use the same BIOS ID as others (e.g 4.1 GA through 4.1u4).
# When this happens, there's absolutely NO way of knowing where on the spectrum you are.
# So, we can either put things on the low end (4.1 GA) or the high end (4.1u4).
# By default we round down: "you're AT LEAST this release."  (though, the report makes it
# sound like "you ARE this release"
# If you like, you can set --minor-error-high to round up.  That would say you're 4.1u4
# even if you're on, say, 4.1u2.  So, it's not always the truth.
my $minor_high    = 0;
# Dump all mapping, doing no reduction for same-BIOS-address detection.  A debug helper.
my $dump          = 0;
# When present, templatefile is a template file of ruby that substitutes [PLACEHOLDER] for
# a set of if-then's to find your ESXi version.
my $templatefile  = undef;
my $help          = 0;

my $usage =<<"EOF";
Usage: $0 [options]

  --minor            Show minor versions               (default $minor_version)
  --minor-error-high Round minor-version guesses high? (default $minor_high)
  --dump             Dump all possible BIOS/versions   (default $dump)
  --template FILE    use <FILE> and substitute our versioning into the [PLACEHOLDER] area.
EOF

GetOptions ('minor'            => \$minor_version,
            'minor-error-high' => \$minor_high,
            'dump'             => \$dump,
            'template=s'       => \$templatefile,
            'help'             => \$help)
or die("Error in command line arguments\n");
die($usage) if ($help);


#####################################################################################
# Read in our JSON, and build a hash for build number -> version number.
# This is pretty much a 'pretty' version of the VMware KB.
open( FH, '<'.$build_num_json_file ) or die "Can't open JSON file $build_num_json_file: $!\n";
my $json_text = join '', <FH>;
close FH;
my $build_num_json = from_json($json_text);

#my @all_builds = @$build_num_json;
my %all_builds = ();

foreach my $build_ref (reverse @$build_num_json) {
    foreach my $buildnum ($build_ref->{'build_number'}, $build_ref->{'installer_build_number'}, ) {
        next unless ($buildnum =~ m#^\d+$#);
        $all_builds{$buildnum}{'major'} = $build_ref->{'major_version'};
        $all_builds{$buildnum}{'minor'} = $build_ref->{'major_version'}.$build_ref->{'interpolated_update_version'};
    }
}
#####################################################################################


#####################################################################################
# This is a 'find' over our dmidecode directory, and from that we build a hash of
# build number -> BIOS Address and Dates
my %all_bios        = ();
my %possible_builds = ();

sub wanted {
    return unless m#^dmidecode\.(\d+)\.txt$#;
    my $buildnum = $1;
    open( FH, '<'.$File::Find::name);
    my @filecontents = <FH>;
    close(FH);
    my ($address, $date);
    foreach my $line (@filecontents) {
        if ($line =~ m#^\s*Address:\s+(0x[0-9A-F]{5})\s*$#) {
            $address = $1;
        } elsif ($line =~ m#^\s*Release\s+Date:\s+(\d{2}/\d{2}/\d{4})\s*$#) {
            $date = $1;
        }
    }
    $all_bios{$buildnum}{'address'} = $address;
    $all_bios{$buildnum}{'date'}    = $date;
    $possible_builds{$address}{$date}{$all_builds{$buildnum}{$minor_version ? 'minor' : 'major'}} = 1;
}

# does dmidecode_dir exist
find(\&wanted, $dmidecode_dir);
#####################################################################################


#####################################################################################
# Here we flatten the list down to unique combinations of address(+date) -> version
# This uses the build number as the glue, but then gets the build number out of the way
# since it has no meaning in the final results.

my %consider = ();
my @line_order = ();
my %last = (); $last{'address'} = ''; $last{'date'} = ''; $last{'version'} = '';
foreach my $buildnum (sort {
            $all_builds{$a}{'minor'} cmp $all_builds{$b}{'minor'} ||
            $a                                <=> $b                    } keys %all_bios) {
    my $address         = $all_bios{$buildnum}{'address'};
    my $date            = $all_bios{$buildnum}{'date'};
    my $version         = $all_builds{$buildnum}{$minor_version ? 'minor' : 'major'};
    if ($dump) {
        print $address .' '. $date .' '. $buildnum .' '. $version ."\n";
        next;
    }
    # Since the only inputs we have are the address and date, we have to cheat here.
    # Find the desired output version (round low or high) and go straight there.
    my @versions_possible = sort keys %{$possible_builds{$address}{$date}};
    $version = $versions_possible[$minor_high ? $#versions_possible : 0];
    # Now that we've rounded $version, check if we've seen it before.
    next if (($last{'address'} eq $address) && ($last{'version'} eq $version));
    $last{'address'} = $address; $last{'date'} = $date; $last{'version'} = $version;
    if ($templatefile) {
        push @line_order, {'address' => $address, 'date' => $date, 'version' => $version, };
        $consider{$address}{$date}{$version} = 1;
    } else {
        print $address .' '. $date .' '. $buildnum .' '. $version ."\n";
    }
}
#####################################################################################

#####################################################################################
if ($templatefile) {
    my @flattened_lines = ();
    foreach my $line_ref (@line_order) {
        my $address         = $line_ref->{'address'};
        my $date            = $line_ref->{'date'};
        my $version         = $line_ref->{'version'};
        if (scalar keys(%{$consider{$address}}) > 1) {
            push @flattened_lines, "elsif biosaddress == '$address' and biosdate == '$date'\n";
        } else {
            push @flattened_lines, "elsif biosaddress == '$address'\n";
        }
        push @flattened_lines, "    vmversion = '$version'\n";
    }
    if (!open( FH, '<'.$templatefile)) {
        print "Could not open $templatefile: $!\nDumping lines:\n";
        print @flattened_lines;
        exit;
    }
    my @file = <FH>;
    close(FH);
    foreach my $line (@file) {
        if ($line !~ m#^(\s*)\[PLACEHOLDER\].*$#) {
            print $line;  next;
        }
        # space padding based on the indention of the placeholder.
        print map { $1.$_ } @flattened_lines;
    }

}
#####################################################################################
