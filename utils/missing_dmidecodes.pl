#!/usr/bin/perl -w
#
# gcox@mozilla
#
use strict;
use warnings;
use JSON;
use File::Find;

my $dmidecode_dir       = '../dmidecode';

#
# This script is a pipeline.  cat raw_data_from_KB.txt | this
# In here, we parse the contents of the VMware KB into a JSON data structure that we can use in,
# well, whatever we want.  It's a basis for making a map for a puppet fact, in our case, but the
# JSON itself might have use for others.
#

my @fields         = qw(osname full_version major_version true_minor_version release_date build_number installer_build_number );
my @addon_fields   = qw(interpolated_update_version interpolated_build_number );

my %sorting_fields = map { $fields[$_] => $_ } ( 0..$#fields );
foreach my $i (0..$#addon_fields) {
    $sorting_fields{$addon_fields[$i]} = $#fields + 1 + $i;
}

my %all_bios        = ();
sub wanted {
    return unless m#^dmidecode\.(\d+)\.txt$#;
    my $buildnum = $1;
    $all_bios{$buildnum} = 1;
}

# does dmidecode_dir exist
find(\&wanted, $dmidecode_dir);

# For each line, make a hash of k/v pairs based on the structure of the KB.
# If VMW changes the layout of the KB, this regexp will probably need tweaking.
my @lines1 = ();
while (<>) {
    next if (m#^\s*$#); # skip empties
    next if (m/^\s*#/); # skip comments
    my $line = $_;
    if (m{^\s*                        # leading spaces if any
           (ESX\S*)\s+                # ESX or ESXi, space
           ((\d\.\d)                  # Major version number  (doublegrab here, full version and breakout)
             (?:\s+|\.\d?\s*)         # either spaces, or, .0(optionalspace) to get rid of stupid cases of
                                      # there being "5.1.0 GA" and "6.0.0b"
           (.*?))                     # A grab-it-all for the descriptor of the release.
           \t                         #   BREAK
           [^\t]+                     # A release name, which we do not currently use   FIXME
           \t                         #   BREAK
           (\s|\d{1,2}/\d{1,2}/\d{4}) # Release date (if they put one in)
           \t                         #   BREAK
           (\d+)                      # Numeric build number
           \t                         #   BREAK
           (\S+)                      # Installer build number (though usually an "NA" or "N/A")
           \s*$}x) {                  # trailing spaces if any
        my @vals = ($1, $2, $3, $4, $5, $6, $7, );
        my %hash = map { $fields[$_] => $vals[$_] } ( 0..$#vals );
        $hash{'line'} = $line;
        push @lines1, \%hash;
    } else {
        chomp;
        print STDERR "Could not match $_\n";
    }
}

# Interpolate a build number and a "well, it's MOSTLY this update version" into variables for
# simplicity's sake.
my @lines2 = ();
my $interpolated_update_version = '';
my $major_version_tracker = "-123456";    # just something that doesn't match a real version
foreach my $line_ref (reverse @lines1) {
    if ($major_version_tracker ne $line_ref->{'major_version'}) {
        $major_version_tracker = $line_ref->{'major_version'};
        $interpolated_update_version = '';
    } elsif ($line_ref->{'true_minor_version'} =~ m#^(?:U|Update )(\d+)#) {
        $interpolated_update_version = 'u'.$1;
    }
    $line_ref->{'interpolated_update_version'} = $interpolated_update_version;

    $line_ref->{'interpolated_build_number'} = ($line_ref->{'installer_build_number'} =~ m#^\d+$#) ? $line_ref->{'installer_build_number'} : $line_ref->{'build_number'};
    print(($all_bios{$line_ref->{'interpolated_build_number'}}) ? 'DONE ' : '     ');
    print $line_ref->{'line'};
}


