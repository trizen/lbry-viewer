package WWW::LbryViewer::VideoCategories;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::LbryViewer::VideoCategories - videoCategory resource handler.

=head1 SYNOPSIS

    use WWW::LbryViewer;
    my $obj = WWW::LbryViewer->new(%opts);
    my $cats = $obj->video_categories();

=head1 SUBROUTINES/METHODS

=cut

=head2 video_categories()

Return video categories for a specific region ID.

=cut

sub video_categories {
    my ($self) = @_;

    return [{id => "featured",     title => "Featured"},
            {id => "popculture",   title => "Pop Culture"},
            {id => "artists",      title => "Artists"},
            {id => "education",    title => "Education"},
            {id => "lifestyle",    title => "Lifestyle"},
            {id => "spooky",       title => "Spooky"},
            {id => "gaming",       title => "Gaming"},
            {id => "tech",         title => "Tech"},
            {id => "comedy",       title => "Comedy"},
            {id => "music",        title => "Music"},
            {id => "sports",       title => "Sports"},
            {id => "universe",     title => "Universe"},
            {id => "finance",      title => "Finance 2.0"},
            {id => "spirituality", title => "Spirituality"},
            {id => "news",         title => "News & Politics"},
            {id => "rabbithole",   title => "Rabbit Hole"},
           ];
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::VideoCategories


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::VideoCategories
