package WWW::LbryViewer::Itags;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::LbryViewer::Itags - Get the YouTube itags.

=head1 SYNOPSIS

    use WWW::LbryViewer::Itags;

    my $yv_itags = WWW::LbryViewer::Itags->new();

    my $itags = $yv_itags->get_itags();
    my $res = $yv_itags->get_resolutions();

=head1 SUBROUTINES/METHODS

=head2 new()

Return the blessed object.

=cut

sub new {
    my ($class) = @_;
    bless {}, $class;
}

=head2 get_itags()

Get a HASH ref with the YouTube itags. {resolution => [itags]}.

Reference: https://en.wikipedia.org/wiki/YouTube#Quality_and_formats

=cut

sub get_itags {
    scalar {

        'best' => [{value => 'b', format => 'mp4'}],

        '1080' => [{value => 'hls-4026', format => 'mp4'},
                   {value => 'hls-316',  format => 'mp4'},
                   {value => 'hls-4432', format => 'mp4'},
                   {value => '1080p',    format => 'mp4'},
                  ],

        '720' => [{value => "hls-176",  format => 'mp4'},
                  {value => "hls-246",  format => 'mp4'},
                  {value => "hls-660",  format => 'mp4'},
                  {value => "hls-2890", format => 'mp4'},
                  {value => "hls-3300", format => 'mp4'},
                  {value => "hls-1460", format => 'mp4'},
                  {value => "720p",     format => 'mp4'},
                 ],

        '480' => [{value => "hls-1567", format => 'mp4'},],
        '480' => [{value => "480p",     format => 'mp4'},],

        '360' => [{value => "hls-140-1", format => 'mp4'},
                  {value => "hls-211",   format => 'mp4'},
                  {value => "hls-105",   format => 'mp4'},
                  {value => "hls-655",   format => 'mp4'},
                  {value => "hls-215",   format => 'mp4'},
                  {value => "hls-525",   format => 'mp4'},
                  {value => "360p",      format => 'mp4'},
                 ],

        '240' => [{value => "240p", format => 'mp4'},],

        '144' => [{value => "hls-140-0", format => 'mp4'},
                  {value => "hls-140",   format => 'mp4'},
                  {value => "hls-70",    format => 'mp4'},
                  {value => "hls-180",   format => 'mp4'},
                  {value => "hls-250",   format => 'mp4'},
                  {value => "144p",      format => 'mp4'},
                 ],

        'audio' => [],
           };
}

=head2 get_resolutions()

Get an ARRAY ref with the supported resolutions ordered from highest to lowest.

=cut

sub get_resolutions {
    my ($self) = @_;

    state $itags = $self->get_itags();
    return [
        grep { exists $itags->{$_} }
          qw(
          best
          2160
          1440
          1080
          720
          480
          360
          240
          144
          audio
          )
    ];
}

sub _find_streaming_url {
    my ($self, %args) = @_;

    my $stream     = $args{stream}     // return;
    my $resolution = $args{resolution} // return;

    foreach my $itag (@{$args{itags}->{$resolution}}) {

        next if not exists $stream->{$itag->{value}};

        my $entry = $stream->{$itag->{value}};

        if (defined($entry->{fps}) and $entry->{fps} >= 50) {
            $args{hfr} || next;    # skip high frame rate (HFR) videos
        }

        if ($itag->{format} eq 'av1') {
            $args{ignore_av1} && next;    # ignore videos in AV1 format
        }

        # Ignored video projections
        if (ref($args{ignored_projections}) eq 'ARRAY') {
            if (grep { lc($entry->{projectionType} // '') eq lc($_) } @{$args{ignored_projections}}) {
                next;
            }
        }

        if ($itag->{split}) {

            $args{split} || next;

            my $video_info = $stream->{$itag->{value}};
            my $audio_info = $self->_find_streaming_url(%args, resolution => 'audio', split => 0);

            if (defined($audio_info)) {
                $video_info->{__AUDIO__} = $audio_info;
                return $video_info;
            }

            next;
        }

        if ($resolution eq 'audio' and $args{prefer_m4a}) {
            if ($itag->{format} ne 'm4a') {
                next;    # skip non-M4A audio URLs
            }
        }

        # Ignore segmented DASH URLs (they load pretty slow in mpv)
        #~ if (not $args{dash}) {
        #~ next if ($entry->{url} =~ m{/api/manifest/dash/});
        #~ }

        return $entry;
    }

    return;
}

=head2 find_streaming_url(%options)

Return the streaming URL which corresponds with the specified resolution.

    (
        urls           => \@streaming_urls,
        resolution     => 'resolution_name',     # from $obj->get_resolutions(),

        hfr            => 1/0,     # include or exclude High Frame Rate videos
        ignore_av1     => 1/0,     # true to ignore videos in AV1 format
        split          => 1/0,     # include or exclude split videos
        m4a_audio      => 1/0,     # incldue or exclude M4A audio files
    )

=cut

sub find_streaming_url {
    my ($self, %args) = @_;

    my $urls_array = $args{urls};
    my $resolution = $args{resolution};

    state $itags = $self->get_itags();

    if (defined($resolution) and $resolution =~ /^([0-9]+)/) {
        $resolution = $1;
    }

    my %stream;
    foreach my $info_ref (@{$urls_array}) {
        if (exists $info_ref->{itag} and exists $info_ref->{url}) {
            $stream{$info_ref->{itag}} = $info_ref;
        }
    }

    # Check if we do recognize all the audio/video formats
    foreach my $stream_itag (keys %stream) {
        my $found_itag = 0;
        foreach my $resolution_itags (values %$itags) {
            foreach my $format (@$resolution_itags) {
                if ($format->{value} eq $stream_itag) {
                    $found_itag = 1;
                    last;
                }
            }
            last if $found_itag;
        }
        if (not $found_itag) {
            say STDERR "[BUG] Itag: $stream_itag is not recognized!";
            require Data::Dump;
            Data::Dump::pp($stream{$stream_itag});
        }
    }

    $args{stream}     = \%stream;
    $args{itags}      = $itags;
    $args{resolution} = $resolution;

    my ($streaming, $found_resolution);

    # Try to find the wanted resolution
    if (defined($resolution) and exists $itags->{$resolution}) {
        $streaming        = $self->_find_streaming_url(%args);
        $found_resolution = $resolution;
    }

    state $resolutions = $self->get_resolutions();

    # Find the nearest available resolution
    if (defined($resolution) and not defined($streaming)) {

        my $end = $#{$resolutions} - 1;    # -1 to ignore 'audio'

        foreach my $i (0 .. $end) {
            if ($resolutions->[$i] eq $resolution) {
                for (my $k = 1 ; ; ++$k) {

                    if ($i + $k > $end and $i - $k < 0) {
                        last;
                    }

                    if ($i + $k <= $end) {    # nearest below

                        my $res = $resolutions->[$i + $k];
                        $streaming = $self->_find_streaming_url(%args, resolution => $res);

                        if (defined($streaming)) {
                            $found_resolution = $res;
                            last;
                        }
                    }

                    if ($i - $k >= 0) {       # nearest above

                        my $res = $resolutions->[$i - $k];
                        $streaming = $self->_find_streaming_url(%args, resolution => $res);

                        if (defined($streaming)) {
                            $found_resolution = $res;
                            last;
                        }
                    }
                }
                last;
            }
        }
    }

    # Otherwise, find the best resolution available
    if (not defined $streaming) {
        foreach my $res (@{$resolutions}) {

            $streaming = $self->_find_streaming_url(%args, resolution => $res);

            if (defined($streaming)) {
                $found_resolution = $res;
                last;
            }
        }
    }

    if (!defined($streaming) and @{$urls_array}) {
        say STDERR "[BUG] Unknown video formats:";

        require Data::Dump;
        Data::Dump::pp($urls_array);

        $streaming        = $urls_array->[-1];
        $found_resolution = '720';
    }

    wantarray ? ($streaming, $found_resolution) : $streaming;
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::Itags


=head1 LICENSE AND COPYRIGHT

Copyright 2012-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::Itags
