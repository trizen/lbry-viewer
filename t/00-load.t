#!perl -T

use 5.014;
use Test::More tests => 1;

BEGIN {
    use_ok( 'WWW::LbryViewer' ) || print "Bail out!\n";
}

diag( "Testing WWW::LbryViewer $WWW::LbryViewer::VERSION, Perl $], $^X" );
