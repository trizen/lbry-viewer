package WWW::LbryViewer::Channels;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::LbryViewer::Channels - Channels interface.

=head1 SYNOPSIS

    use WWW::LbryViewer;
    my $obj = WWW::LbryViewer->new(%opts);
    my $videos = $obj->channels_from_categoryID($category_id);

=head1 SUBROUTINES/METHODS

=cut

sub _make_channels_url {
    my ($self, %opts) = @_;
    return $self->_make_feed_url('channels', %opts);
}

sub videos_from_channel_id {
    my ($self, $channel_id) = @_;

    if (my $results = $self->lbry_channel_uploads($channel_id)) {
        return $results;
    }

    if (my $results = $self->yt_channel_uploads($channel_id)) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/videos");
    return $self->_get_results($url);
}

sub videos_from_username {
    my ($self, $channel_id) = @_;
    $self->videos_from_channel_id($channel_id);
}

=head2 popular_videos($channel_id)

Get the most popular videos for a given channel ID.

=cut

sub popular_videos {
    my ($self, $channel_id) = @_;

    if (not defined($channel_id)) {    # trending popular videos
        return $self->_get_results($self->_make_feed_url('popular'));
    }

    # TODO: implement support for popular LBRY videos for a channel
    return $self->videos_from_channel_id($channel_id);

    if (my $results = $self->yt_channel_uploads($channel_id, sort_by => 'popular')) {
        return $results;
    }

    my $url = $self->_make_feed_url("channels/$channel_id/videos", sort_by => 'popular');
    return $self->_get_results($url);
}

=head2 channels_from_categoryID($category_id)

Return the YouTube channels associated with the specified category.

=head2 channels_info($channel_id)

Return information for the comma-separated list of the YouTube channel ID(s).

=head1 Channel details

For all functions, C<$channels->{results}{items}> contains:

=cut

{
    no strict 'refs';

    foreach my $method (
                        {
                         key  => 'categoryId',
                         name => 'channels_from_guide_category',
                        },
                        {
                         key  => 'id',
                         name => 'channels_info',
                        },
                        {
                         key  => 'forUsername',
                         name => 'channels_from_username',
                        },
      ) {
        *{__PACKAGE__ . '::' . $method->{name}} = sub {
            my ($self, $channel_id) = @_;
            return $self->_get_results($self->_make_channels_url($method->{key} => $channel_id));
        };
    }

    foreach my $part (qw(id contentDetails statistics topicDetails)) {
        *{__PACKAGE__ . '::' . 'channels_' . $part} = sub {
            my ($self, $id) = @_;
            return $self->_get_results($self->_make_channels_url(id => $id, part => $part));
        };
    }
}

=head2 channel_id_from_username($username)

Return the channel ID for an username.

=cut

sub channel_id_from_username {
    my ($self, $username) = @_;

    state $cache = {};

    if (exists $cache->{username}) {
        return $cache->{username};
    }

    if (defined(my $id = $self->yt_channel_id($username))) {
        if (ref($id) eq '' and $id =~ /\S/) {
            $cache->{$username} = $id;
            return $id;
        }
    }

    # A channel's username (if it doesn't include spaces) is also valid in place of ucid.
    if ($username =~ /\w/ and not $username =~ /\s/) {
        return $username;
    }

    # Unable to resolve channel name to channel ID (return as it is)
    return $username;
}

=head2 channel_title_from_id($channel_id)

Return the channel title for a given channel ID.

=cut

sub channel_title_from_id {
    my ($self, $channel_id) = @_;

    $channel_id // return;

    state $cache = {};

    if (exists $cache->{channel_id}) {
        return $cache->{channel_id};
    }

    if (defined(my $title = $self->yt_channel_title($channel_id))) {
        if (ref($title) eq '' and $title =~ /\S/) {
            $cache->{$channel_id} = $title;
            return $title;
        }
    }

    my $info = $self->channels_info($channel_id) // return;

    (    ref($info) eq 'HASH'
     and ref($info->{results}) eq 'HASH'
     and ref($info->{results}{items}) eq 'ARRAY'
     and ref($info->{results}{items}[0]) eq 'HASH')
      ? $info->{results}{items}[0]{snippet}{title}
      : ();
}

=head2 channels_contentDetails($channelID)

=head2 channels_statistics($channelID);

=head2 channels_topicDetails($channelID)

=cut

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::Channels


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::Channels
