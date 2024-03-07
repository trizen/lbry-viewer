package WWW::LbryViewer::RegularExpressions;

use utf8;
use 5.014;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

=head1 NAME

WWW::LbryViewer::RegularExpressions - Various utils.

=head1 SYNOPSIS

    use WWW::LbryViewer::RegularExpressions;
    use WWW::LbryViewer::RegularExpressions ($get_video_id_re);

=cut

my $opt_begin_chars = q{:;=};    # stdin option valid begin chars

# Options
our $range_num_re        = qr{^([0-9]{1,3}+)(?>-|\.\.)([0-9]{1,3}+)?\z};
our $digit_or_equal_re   = qr/(?(?=[1-9])|=)/;
our $non_digit_or_opt_re = qr{^(?!$range_num_re)(?>[0-9]{1,3}[^0-9]|[0-9]{4}|[^0-9$opt_begin_chars])};

# Generic name
our $generic_name_re     = qr/[a-zA-Z0-9_.\-\@:]{3,128}/;
our $valid_channel_id_re = qr{(?:^|/)(?<channel_id>\@$generic_name_re)(?:/|\z)};

our $get_channel_videos_id_re    = qr{^.*/(?:channel|c)/(?<channel_id>(?:[%\w]+(?:[-.]++[%\w]++)*|$generic_name_re))};
our $get_channel_playlists_id_re = qr{$get_channel_videos_id_re/playlists};

our $get_username_videos_re    = qr{^.*/user/(?<username>[-.\w]+)};
our $get_username_playlists_re = qr{$get_username_videos_re/playlists};

# Video ID
my $video_id_re = qr{(?>\@(?>[^/]+/[^/]+|[^/]+)|[^/]+[/:][a-f0-9]{40}\b|[^/]+:[0-9]+\b)};
our $valid_video_id_re = qr{^$video_id_re\z};
our $get_video_id_re   = qr{/(?<video_id>$video_id_re)$};

# Playlist ID
our $valid_playlist_id_re = qr{^$generic_name_re\z};
our $get_playlist_id_re   = qr{(?:(?:(?>playlist\?list|view_play_list\?p|list)=)|\w#p/c/)(?<playlist_id>$generic_name_re)};

our $valid_opt_re = qr{^[$opt_begin_chars]([A-Za-z]++(?:-[A-Za-z]++)?(?>${digit_or_equal_re}.*)?)$};

our @EXPORT = qw(
  $generic_name_re
  $range_num_re
  $digit_or_equal_re
  $non_digit_or_opt_re
  $valid_channel_id_re
  $valid_video_id_re
  $get_video_id_re
  $valid_playlist_id_re
  $get_playlist_id_re
  $valid_opt_re
  $get_channel_videos_id_re
  $get_channel_playlists_id_re
  $get_username_videos_re
  $get_username_playlists_re
);

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::RegularExpressions


=head1 LICENSE AND COPYRIGHT

Copyright 2012-2013 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::RegularExpressions
