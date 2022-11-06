package WWW::LbryViewer::Search;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::LbryViewer::Search - Search for stuff on YouTube

=head1 SYNOPSIS

    use WWW::LbryViewer;
    my $obj = WWW::LbryViewer->new(%opts);
    $obj->search_videos(@keywords);

=head1 SUBROUTINES/METHODS

=cut

sub _make_search_url {
    my ($self, %opts) = @_;

    my @features;

    if (defined(my $vd = $self->get_videoDefinition)) {
        if ($vd eq 'high') {
            push @features, 'hd';
        }
    }

    if (defined(my $vc = $self->get_videoCaption)) {
        if ($vc eq 'true' or $vc eq '1') {
            push @features, 'subtitles';
        }
    }

    if (defined(my $vd = $self->get_videoDimension)) {
        if ($vd eq '3d') {
            push @features, '3d';
        }
    }

    if (defined(my $license = $self->get_videoLicense)) {
        if ($license eq 'creative_commons') {
            push @features, 'creative_commons';
        }
    }

    return $self->_make_feed_url(
        'search',

        region   => $self->get_region,
        sort_by  => $self->get_order,
        date     => $self->get_date,
        page     => $self->page_token,
        duration => $self->get_videoDuration,

        (@features ? (features => join(',', @features)) : ()),

        %opts,
    );
}

=head2 search_for($types,$keywords;\%args)

Search for a list of types (comma-separated).

=cut

sub search_for {
    my ($self, $type, $keywords, $args) = @_;

    if (ref($args) ne 'HASH') {
        $args = {};
    }

    $keywords //= [];

    if (ref($keywords) ne 'ARRAY') {
        $keywords = [split ' ', $keywords];
    }

    $keywords = $self->escape_string(join(' ', @{$keywords}));

    # Search in a channel's videos
    if (defined(my $channel_id = $self->get_channelId)) {

        $self->set_channelId();    # clear the channel ID

        if (my $results = $self->yt_channel_search($channel_id, q => $keywords, type => $type, %$args)) {
            return $results;
        }

        my $url = $self->_make_feed_url("channels/search/$channel_id", q => $keywords);
        return $self->_get_results($url);
    }

    if (my $results = $self->lbry_search(q => $keywords, type => $type, %$args)) {
        return $results;
    }

    return {};
}

{
    no strict 'refs';

    foreach my $pair (
                      {
                       name => 'videos',
                       type => 'video',
                      },
                      {
                       name => 'playlists',
                       type => 'playlist',
                      },
                      {
                       name => 'channels',
                       type => 'channel',
                      },
                      {
                       name => 'all',
                       type => 'all',
                      }
      ) {
        *{__PACKAGE__ . '::' . "search_$pair->{name}"} = sub {
            my $self = shift;
            $self->search_for($pair->{type}, @_);
        };
    }
}

=head2 search_videos($keywords;\%args)

Search and return the found video results.

=cut

=head2 search_playlists($keywords;\%args)

Search and return the found playlists.

=cut

=head2 search_channels($keywords;\%args)

Search and return the found channels.

=cut

=head2 search_all($keywords;\%args)

Search and return the results.

=cut

=head2 related_to_videoID($id)

Retrieves a list of videos that are related to the video ID.

=cut

sub related_to_videoID {
    my ($self, $videoID) = @_;

    my $info           = $self->lbry_video_info(id => $videoID);
    my $related_videos = $info->{related_videos} // [];

    return
      scalar {
              url     => undef,
              results => $related_videos,
             };
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::Search


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::Search
