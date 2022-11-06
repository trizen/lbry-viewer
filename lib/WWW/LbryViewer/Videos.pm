package WWW::LbryViewer::Videos;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::LbryViewer::Videos - videos handler.

=head1 SYNOPSIS

    use WWW::LbryViewer;
    my $obj = WWW::LbryViewer->new(%opts);
    my $info = $obj->video_details($videoID);

=head1 SUBROUTINES/METHODS

=cut

sub _make_videos_url {
    my ($self, %opts) = @_;
    return $self->_make_feed_url('videos', %opts);
}

{
    no strict 'refs';
    foreach my $part (
                      qw(
                      id
                      snippet
                      contentDetails
                      fileDetails
                      player
                      liveStreamingDetails
                      processingDetails
                      recordingDetails
                      statistics
                      status
                      suggestions
                      topicDetails
                      )
      ) {
        *{__PACKAGE__ . '::' . 'video_' . $part} = sub {
            my ($self, $id) = @_;
            return $self->_get_results($self->_make_videos_url(id => $id, part => $part));
        };
    }
}

=head2 trending_videos_from_category($category_id)

Get popular videos from a category ID.

=cut

sub trending_videos_from_category {
    my ($self, $category) = @_;

    if (defined($category) and $category eq 'featured') {
        return $self->popular_videos;
    }

    return $self->lbry_category_videos($category);
}

=head2 send_rating_to_video($videoID, $rating)

Send rating to a video. $rating can be either 'like' or 'dislike'.

=cut

sub send_rating_to_video {
    my ($self, $video_id, $rating) = @_;

    if ($rating eq 'none' or $rating eq 'like' or $rating eq 'dislike') {
        my $url = $self->_simple_feeds_url('videos/rate', id => $video_id, rating => $rating);
        return defined($self->lwp_post($url, $self->_auth_lwp_header()));
    }

    return;
}

=head2 like_video($videoID)

Like a video. Returns true on success.

=cut

sub like_video {
    my ($self, $video_id) = @_;
    $self->send_rating_to_video($video_id, 'like');
}

=head2 dislike_video($videoID)

Dislike a video. Returns true on success.

=cut

sub dislike_video {
    my ($self, $video_id) = @_;
    $self->send_rating_to_video($video_id, 'dislike');
}

sub _ytdl_video_details {
    my ($self, $id) = @_;
    $self->_info_from_ytdl($id);
}

sub _fallback_video_details {
    my ($self, $id, $fields) = @_;

    if ($self->get_debug) {
        say STDERR ":: Extracting video info using the fallback method...";
    }

    my $info = $self->_ytdl_video_details($id);

    if (defined($info) and ref($info) eq 'HASH') {
        return scalar {

            extra_info => 1,
            type       => 'video',

            title   => $info->{fulltitle} // $info->{title},
            videoId => $id,

#<<<
            videoThumbnails => [
                    map {
                        scalar {
                              quality => 'medium',
                              url     => $_->{url},
                              width   => $_->{width},
                              height  => $_->{height},
                        }
                    } @{$info->{thumbnails}}
            ],
#>>>

            liveNow       => ($info->{is_live} ? 1 : 0),
            description   => $info->{description},
            lengthSeconds => $info->{duration},

            likeCount    => $info->{like_count},
            dislikeCount => $info->{dislike_count},

            category    => eval { $info->{categories}[0] } // $info->{category},
            publishDate => $info->{upload_date}            // $info->{release_date},

            keywords  => $info->{tags},
            viewCount => $info->{view_count},

            author => $info->{channel},

            #authorId => (split(/\//, $id))[0],
            authorId => (split(/\//, ($info->{channel_url} // '')))[-1] // '',
            rating   => $info->{average_rating},
        };
    }
    else {

        if ($self->get_debug) {
            say STDERR ":: The fallback method failed. Trying the main method..";
        }

        if (defined(my $info = $self->lbry_video_info(id => $id))) {
            return $info;
        }
    }

    return {};
}

sub video_details {
    my ($self, $id, $fields) = @_;

    # Extract info from the Librarian website
    if (not $self->get_force_fallback and defined(my $info = $self->lbry_video_info(id => $id))) {
        return $info;
    }

    # Extract info with youtube-dl / yt-dlp
    return $self->_fallback_video_details($id, $fields);
}

=head2 Return details

Each function returns a HASH ref, with a key called 'results', and another key, called 'url'.

The 'url' key contains a string, which is the URL for the retrieved content.

The 'results' key contains another HASH ref with the keys 'etag', 'items' and 'kind'.
From the 'results' key, only the 'items' are relevant to us. This key contains an ARRAY ref,
with a HASH ref for each result. An example of the item array's content are shown below.

=cut

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::Videos


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::Videos
