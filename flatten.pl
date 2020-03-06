#! /usr/bin/perl

package test;
use strict;

open(READ, "<$ARGV[0]") || die "couldn't open $ARGV[0]" && usage();
open(WRITEM, ">/tmp/mapping-flat.txt") || die "couldn't open output";
open(WRITEI, ">/tmp/imageContentSourcePolicy-flat.yaml") || die "couldn't open output";

print WRITEI "apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: redhat-operators
spec:
  repositoryDigestMirrors:
";

foreach my $line (<READ>) {
    my ($source, $dest) = split('=', $line);
    my ($dbase, $dnest, $dimage) = $dest =~ m/^(.*)\/(.*)\/(.*)$/;
    #print "$dbase : $dnest : $dimage\n";
    print WRITEM "$source=$dbase/$dimage\n";
    print WRITEI "  - mirrors:
    - $dbase/$dimage
    soure: $source\n";
}
close READ;
close WRITEM;
close WRITEI;

print STDERR <<'EOF';

Wrote:

    /tmp/mapping-flat.txt
    /tmp/imageContentSourcePolicy-flat.yaml

Now run:

    while read line; do oc image mirror $line; done < /tmp/mapping-flat.txt
    oc apply -f /tmp/imageContentSourcePolicy-flat.yaml

EOF

sub usage {
    print STDERR <<EOF;
usage:  perl $0 mapping.txt

    Flattens mapping.txt file so can be imported into Registry that does not support Nesting repositories. Outputs to:

    /tmp/mapping-flat.txt
    /tmp/imageContentSourcePolicy-flat.yaml

EOF
    exit 1;
}
