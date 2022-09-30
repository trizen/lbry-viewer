package WWW::LbryViewer::PlaylistItems;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::LbryViewer::PlaylistItems - Manage playlist entries.

=head1 SYNOPSIS

    use WWW::LbryViewer;
    my $obj = WWW::LbryViewer->new(%opts);
    my $videos = $obj->videos_from_playlistID($playlist_id);

=head1 SUBROUTINES/METHODS

=cut

sub _make_playlistItems_url {
    my ($self, %opts) = @_;
    return
      $self->_make_feed_url(
                            'playlistItems',
                            pageToken => $self->page_token,
                            %opts
                           );
}

=head2 videos_from_playlist_id($playlist_id)

Get videos from a specific playlistID.

=cut

sub videos_from_playlist_id {
    my ($self, $id) = @_;

    if (my $results = $self->yt_playlist_videos($id)) {
        return $results;
    }

    my $url = $self->_make_feed_url("playlists/$id");
    $self->_get_results($url);
}

=head2 favorites($channel_id)

=head2 uploads($channel_id)

=head2 likes($channel_id)

Get the favorites, uploads and likes for a given channel ID.

=cut

=head2 favorites_from_username($username)

=head2 uploads_from_username($username)

=head2 likes_from_username($username)

Get the favorites, uploads and likes for a given YouTube username.

=cut

{
    no strict 'refs';
    foreach my $name (qw(favorites uploads likes)) {

        *{__PACKAGE__ . '::' . $name . '_from_username'} = sub {
            my ($self, $username) = @_;
            $self->videos_from_username($username);
        };

        *{__PACKAGE__ . '::' . $name} = sub {
            my ($self, $channel_id) = @_;
            $self->videos_from_channel_id($channel_id);
        };
    }
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::PlaylistItems


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::PlaylistItems
