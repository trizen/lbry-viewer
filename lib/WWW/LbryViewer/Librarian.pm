package WWW::LbryViewer::Librarian;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::LbryViewer::Librarian - Extract Librarian data.

=head1 SYNOPSIS

    use WWW::LbryViewer;
    my $obj = WWW::LbryViewer->new(%opts);

    my $results   = $obj->lbry_search(q => $keywords);
    my $playlists = $obj->lbry_channel_created_playlists($channel_ID);

=head1 SUBROUTINES/METHODS

=cut

sub _time_to_seconds {
    my ($time) = @_;

    my ($hours, $minutes, $seconds) = (0, 0, 0);

    if ($time =~ /(\d+):(\d+):(\d+)/) {
        ($hours, $minutes, $seconds) = ($1, $2, $3);
    }
    elsif ($time =~ /(\d+):(\d+)/) {
        ($minutes, $seconds) = ($1, $2);
    }
    elsif ($time =~ /(\d+)/) {
        $seconds = $1;
    }

    $hours * 3600 + $minutes * 60 + $seconds;
}

sub _human_number_to_int {
    my ($text) = @_;

    $text // return undef;

    # 7.6K -> 7600; 7.6M -> 7600000
    if ($text =~ /([\d,.]+)\s*([KMB])/i) {

        my $v = $1;
        my $u = $2;
        my $m = ($u eq 'K' ? 1e3 : ($u eq 'M' ? 1e6 : ($u eq 'B' ? 1e9 : 1)));

        $v =~ tr/,/./;

        return int($v * $m);
    }

    if ($text =~ /([\d,.]+)/) {
        my $v = $1;
        $v =~ tr/,.//d;
        return int($v);
    }

    return 0;
}

sub _thumbnail_quality {
    my ($width) = @_;

    $width // return 'medium';

    if ($width == 1280) {
        return "maxres";
    }

    if ($width == 640) {
        return "sddefault";
    }

    if ($width == 480) {
        return 'high';
    }

    if ($width == 320) {
        return 'medium';
    }

    if ($width == 120) {
        return 'default';
    }

    if ($width <= 120) {
        return 'small';
    }

    if ($width <= 176) {
        return 'medium';
    }

    if ($width <= 480) {
        return 'high';
    }

    if ($width <= 640) {
        return 'sddefault';
    }

    if ($width <= 1280) {
        return "maxres";
    }

    return 'medium';
}

sub _fix_url_protocol {
    my ($self, $url) = @_;

    $url // return undef;

    if ($url =~ m{^https://}) {    # ok
        return $url;
    }
    if ($url =~ s{^.*?//}{}) {
        return "https://" . $url;
    }
    if ($url =~ /^\w+\./) {
        return "https://" . $url;
    }

    if ($url =~ m{^/}) {
        return $self->get_librarian_url . $url;
    }

    return $url;
}

sub _unscramble {
    my ($str) = @_;

    my $i = my $l = length($str);

    $str =~ s/(.)(.{$i})/$2$1/sg while (--$i > 0);
    $str =~ s/(.)(.{$i})/$2$1/sg while (++$i < $l);

    return $str;
}

sub _extract_youtube_mix {
    my ($self, $data) = @_;

    my $info   = eval { $data->{callToAction}{watchCardHeroVideoRenderer} } || return;
    my $header = eval { $data->{header}{watchCardRichHeaderRenderer} };

    my %mix;

    $mix{type} = 'playlist';

    $mix{title} =
      eval    { $header->{title}{runs}[0]{text} }
      // eval { $info->{accessibility}{accessibilityData}{label} }
      // eval { $info->{callToActionButton}{callToActionButtonRenderer}{label}{runs}[0]{text} } // 'Youtube Mix';

    $mix{playlistId} = eval { $info->{navigationEndpoint}{watchEndpoint}{playlistId} } || return;

    $mix{playlistThumbnail} = eval { $self->_fix_url_protocol($header->{avatar}{thumbnails}[0]{url}) }
      // eval { $self->_fix_url_protocol($info->{heroImage}{collageHeroImageRenderer}{leftThumbnail}{thumbnails}[0]{url}) };

    $mix{description} = _extract_description({title => $info});

    $mix{author}   = eval { $header->{title}{runs}[0]{text} }                              // "YouTube";
    $mix{authorId} = eval { $header->{titleNavigationEndpoint}{browseEndpoint}{browseId} } // "youtube";

    return \%mix;
}

sub _extract_author_name {
    my ($info) = @_;
    eval { $info->{longBylineText}{runs}[0]{text} } // eval { $info->{shortBylineText}{runs}[0]{text} };
}

sub _extract_video_id {
    my ($info) = @_;
    eval { $info->{videoId} } || eval { $info->{navigationEndpoint}{watchEndpoint}{videoId} } || undef;
}

sub _extract_length_seconds {
    my ($time) = @_;
    _time_to_seconds($time);
}

sub _extract_published_text {
    my ($text) = @_;

    if ($text =~ /(\d+)\s+(\w+)/) {
        return "$1 $2 ago";
    }

    if ($text =~ /(\d+)\s*(\w+)/) {
        return "$1 $2 ago";
    }

    return $text;
}

sub _extract_published_date {
    my ($date) = @_;

    require Encode;
    require Time::Piece;

    my $time = eval { Time::Piece->strptime($date, '%B %d, %Y') } // return;
    return Encode::decode_utf8($time->strftime('%Y%m%d'));
}

sub _extract_channel_id {
    my ($info) = @_;
    eval      { $info->{channelId} }
      // eval { $info->{shortBylineText}{runs}[0]{navigationEndpoint}{browseEndpoint}{browseId} }
      // eval { $info->{navigationEndpoint}{browseEndpoint}{browseId} };
}

sub _extract_view_count_text {
    my ($info) = @_;
    eval { $info->{shortViewCountText}{runs}[0]{text} };
}

sub _extract_thumbnails {
    my ($self, $info) = @_;
    eval {
        [
         map {
             my %thumb = %$_;

             $thumb{quality} = _thumbnail_quality($thumb{width});
             $thumb{url}     = $thumb{'-src'};

             if ($thumb{url} =~ /\?(.+)/) {
                 my %params = $self->parse_query_string($1);
                 if (defined($params{url})) {

                     $thumb{url} = $params{url};

                     if ($thumb{url} !~ /^https?:/) {
                         require MIME::Base64;
                         $thumb{url} = MIME::Base64::decode_base64($thumb{url});
                     }
                 }
             }

             $thumb{url} = $self->_fix_url_protocol($thumb{url});

             \%thumb;
         } @{$info}
        ]
    };
}

sub _extract_playlist_thumbnail {
    my ($self, $info) = @_;
    eval {
        $self->_fix_url_protocol(
                         (
                          grep { _thumbnail_quality($_->{width}) =~ /medium|high/ }
                            @{$info->{thumbnailRenderer}{playlistVideoThumbnailRenderer}{thumbnail}{thumbnails}}
                         )[0]{url} // $info->{thumbnailRenderer}{playlistVideoThumbnailRenderer}{thumbnail}{thumbnails}[0]{url}
        );
    } // eval {
        $self->_fix_url_protocol(
                          (grep { _thumbnail_quality($_->{width}) =~ /medium|high/ } @{$info->{thumbnail}{thumbnails}})[0]{url}
                            // $info->{thumbnail}{thumbnails}[0]{url});
    };
}

sub _extract_title {
    my ($info) = @_;
    eval { $info->{title}{runs}[0]{text} } // eval { $info->{title}{accessibility}{accessibilityData}{label} };
}

sub _extract_description {
    my ($info) = @_;

    # FIXME: this is not the video description
    eval { $info->{title}{accessibility}{accessibilityData}{label} };
}

sub _extract_view_count {
    my ($text) = @_;
    _human_number_to_int($text || 0);
}

sub _extract_video_count {
    my ($text) = @_;
    _human_number_to_int($text || 0);
}

sub _extract_subscriber_count {
    my ($text) = @_;
    _human_number_to_int($text || 0);
}

sub _extract_playlist_id {
    my ($info) = @_;
    eval { $info->{playlistId} };
}

sub _extract_itemSection_entry {
    my ($self, $data, %args) = @_;

    ref($data) eq 'HASH' or return;

    $args{type} //= 'video';

    # Video
    if ($args{type} eq 'video' and defined($data->{'-class'}) and $data->{'-class'} eq 'video') {

        my %video;

        my $info  = $data->{div};
        my $links = $data->{p};

        my $is_video       = 0;
        my $published_date = '';

        foreach my $entry (@{$info}) {

            if ($entry->{'-class'} eq 'thumbnailWrapper') {
                my $link = $entry->{a}[0];
                $video{videoId}         = ($link->{'-href'} =~ s{^/}{}r);
                $video{videoThumbnails} = $self->_extract_thumbnails($link->{img});

                my $p = $entry->{p}[0];
                if (defined($p->{'#text'})) {
                    $video{lengthSeconds} = _extract_length_seconds($p->{'#text'}) || 0;
                }
            }

            if ($entry->{'-class'} eq 'claimMeta') {
                $is_video = 1;
                my $p = $entry->{p};
                $video{publishedText} = _extract_published_text($p->[0]{'#text'});
                $published_date       = $p->[0]{'-title'};
                $video{publishDate}   = _extract_published_date($p->[0]{'-title'});
                $video{viewCount}     = _extract_view_count($p->[1]);
                $video{viewCountText} = $p->[1];
            }
        }

        $video{title}    = $links->[0]{a}[0]{'#text'};
        $video{author}   = $links->[1]{a}[0]{'#text'} // $links->[0]{a}[0]{'#text'};
        $video{authorId} = (($links->[1]{a}[0]{'-href'} // $links->[0]{a}[0]{'-href'}) =~ s{^/}{}r);

        # Probably it's a channel
        if (not $is_video) {
            return $self->_extract_itemSection_entry($data, %args, type => 'channel');
        }

        $video{title} // return;

        $video{lengthSeconds} //= 0;
        $video{type}          //= 'video';
        $video{liveNow}     = ($video{lengthSeconds} == 0);    # maybe live?
        $video{description} = $video{title};

        return \%video;
    }

    # Playlist
    if ($args{type} eq 'playlist') {    # TODO

        my %playlist;
        my $info = $data->{compactPlaylistRenderer};

        $playlist{type} = 'playlist';

        $playlist{title}             = _extract_title($info)       // return;
        $playlist{playlistId}        = _extract_playlist_id($info) // return;
        $playlist{author}            = _extract_author_name($info);
        $playlist{authorId}          = _extract_channel_id($info);
        $playlist{videoCount}        = _extract_video_count($info);
        $playlist{playlistThumbnail} = $self->_extract_playlist_thumbnail($info);
        $playlist{description}       = _extract_description($info);

        return \%playlist;
    }

    # Channel
    if ($args{type} eq 'channel') {

        my %channel;

        my $info  = $data->{div};
        my $links = $data->{p};

        foreach my $entry (@{$info}) {
            if ($entry->{'-class'} eq 'thumbnailWrapper') {
                my $link = $entry->{a}[0];
                $channel{authorId}         = ($link->{'-href'} =~ s{^/}{}r);
                $channel{authorThumbnails} = $self->_extract_thumbnails($link->{img});
            }
        }

        $channel{author}   = $links->[0]{a}[0]{'#text'};
        $channel{authorId} = (($links->[1]{a}[0]{'-href'} // $links->[0]{a}[0]{'-href'}) =~ s{^/}{}r);

        if ($links->[2]{'#text'} =~ /([\d,.]+\s*[KMB]?)\s*followers\s*([\d,.]+\s*[KMB]?)\s*uploads/i) {
            my ($subs, $uploads) = ($1, $2);
            $channel{subCount}   = _extract_subscriber_count($subs);
            $channel{videoCount} = _extract_video_count($uploads);
        }

        $channel{type}        = 'channel';
        $channel{title}       = $channel{author};
        $channel{description} = $channel{author};

        return \%channel;
    }

    return;
}

sub _parse_itemSection {
    my ($self, $entry, %args) = @_;

    eval { ref($entry->{contents}) eq 'ARRAY' } || return;

    my @results;

    foreach my $entry (@{$entry->{contents}}) {

        my $item = $self->_extract_itemSection_entry($entry, %args);

        if (defined($item) and ref($item) eq 'HASH') {
            push @results, $item;
        }
    }

    if (exists($entry->{continuations}) and ref($entry->{continuations}) eq 'ARRAY') {

        my $token = eval { $entry->{continuations}[0]{nextContinuationData}{continuation} };

        if (defined($token)) {
            push @results,
              scalar {
                      type  => 'nextpage',
                      token => "ytplaylist:$args{type}:$token",
                     };
        }
    }

    return @results;
}

sub _parse_itemSection_nextpage {
    my ($self, $entry, %args) = @_;

    eval { ref($entry->{contents}) eq 'ARRAY' } || return;

    foreach my $entry (@{$entry->{contents}}) {

        # Continuation page
        if (exists $entry->{continuationItemRenderer}) {

            my $info  = $entry->{continuationItemRenderer};
            my $token = eval { $info->{continuationEndpoint}{continuationCommand}{token} };

            if (defined($token)) {
                return
                  scalar {
                          type  => 'nextpage',
                          token => "ytbrowse:$args{type}:$token",
                         };
            }
        }
    }

    return;
}

sub _extract_sectionList_results {
    my ($self, $data, %args) = @_;

    $data // return;
    ref($data) eq 'HASH' or return;
    $data->{contents} // return;
    ref($data->{contents}) eq 'ARRAY' or return;

    my @results;

    foreach my $entry (@{$data->{contents}}) {

        # Playlists
        if (eval { ref($entry->{shelfRenderer}{content}{verticalListRenderer}{items}) eq 'ARRAY' }) {
            my $res = {contents => $entry->{shelfRenderer}{content}{verticalListRenderer}{items}};
            push @results, $self->_parse_itemSection($res, %args);
            push @results, $self->_parse_itemSection_nextpage($res, %args);
            next;
        }

        # Playlist videos
        if (eval { ref($entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer}{contents}) eq 'ARRAY' }) {
            my $res = $entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer};
            push @results, $self->_parse_itemSection($res, %args);
            push @results, $self->_parse_itemSection_nextpage($res, %args);
            next;
        }

        # YouTube Mix
        if ($args{type} eq 'all' and exists $entry->{universalWatchCardRenderer}) {

            my $mix = $self->_extract_youtube_mix($entry->{universalWatchCardRenderer});

            if (defined($mix)) {
                push(@results, $mix);
            }
        }

        # Video results
        if (exists $entry->{itemSectionRenderer}) {
            my $res = $entry->{itemSectionRenderer};
            push @results, $self->_parse_itemSection($res, %args);
            push @results, $self->_parse_itemSection_nextpage($res, %args);
        }

        # Continuation page
        if (exists $entry->{continuationItemRenderer}) {

            my $info  = $entry->{continuationItemRenderer};
            my $token = eval { $info->{continuationEndpoint}{continuationCommand}{token} };

            if (defined($token)) {
                push @results,
                  scalar {
                          type  => 'nextpage',
                          token => "ytsearch:$args{type}:$token",
                         };
            }
        }
    }

    if (@results and exists $data->{continuations}) {
        push @results, $self->_parse_itemSection($data, %args);
    }

    return @results;
}

sub _extract_channel_header {
    my ($self, $data, %args) = @_;
    eval { $data->{header}{c4TabbedHeaderRenderer} } // eval { $data->{metadata}{channelMetadataRenderer} };
}

sub _add_author_to_results {
    my ($self, $data, $results, %args) = @_;

    my $header = $self->_extract_channel_header($data, %args);

    my $channel_id   = eval { $header->{channelId} } // eval { $header->{externalId} };
    my $channel_name = eval { $header->{title} };

    foreach my $result (@$results) {
        if (ref($result) eq 'HASH') {
            $result->{author}   = $channel_name if defined($channel_name);
            $result->{authorId} = $channel_id   if defined($channel_id);
        }
    }

    return 1;
}

sub _find_sectionList {
    my ($self, $data) = @_;

    $data // return undef;
    ref($data) eq 'HASH' or return undef;

    if (exists($data->{alerts})) {
        if (
            ref($data->{alerts}) eq 'ARRAY' and grep {
                eval { $_->{alertRenderer}{type} =~ /error/i }
            } @{$data->{alerts}}
          ) {
            return undef;
        }
    }

    if (not exists $data->{contents}) {
        return undef;
    }

    eval {
        (
         grep {
             eval { exists($_->{tabRenderer}{content}{sectionListRenderer}{contents}) }
         } @{$data->{contents}{singleColumnBrowseResultsRenderer}{tabs}}
        )[0]{tabRenderer}{content}{sectionListRenderer};
    } // undef;
}

sub _extract_channel_uploads {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($data), %args);
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _extract_channel_playlists {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($data), %args);
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _extract_playlist_videos {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($data), %args);
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _get_initial_data {
    my ($self, $url) = @_;

    $self->get_prefer_invidious() and return;

    my $content = $self->lwp_get($url) // return;

    if ($content =~ m{var\s+ytInitialData\s*=\s*'(.*?)'}is) {
        my $json = $1;

        $json =~ s{\\x([[:xdigit:]]{2})}{chr(hex($1))}ge;
        $json =~ s{\\u([[:xdigit:]]{4})}{chr(hex($1))}ge;
        $json =~ s{\\(["&])}{$1}g;

        my $hash = $self->parse_utf8_json_string($json);
        return $hash;
    }

    if ($content =~ m{<div id="initial-data"><!--(.*?)--></div>}is) {
        my $json = $1;
        my $hash = $self->parse_utf8_json_string($json);
        return $hash;
    }

    return;
}

sub _channel_data {
    my ($self, $channel, %args) = @_;

    # TODO: implement
}

sub _prepare_results_for_return {
    my ($self, $results, %args) = @_;

    (defined($results) and ref($results) eq 'ARRAY') || return;

    my @results = @$results;

    @results || return;

    if (@results and $results[-1]{type} eq 'nextpage') {

        my $nextpage = pop(@results);

        if (defined($nextpage->{token}) and @results) {

            if ($self->get_debug) {
                say STDERR ":: Returning results with a continuation page token...";
            }

            return {
                    url     => $args{url},
                    results => {
                                entries      => \@results,
                                continuation => $nextpage->{token},
                               },
                   };
        }
    }

    my $url = $args{url};

    if ($url =~ m{^https://m\.youtube\.com}) {
        $url = undef;
    }

    return {
            url     => $url,
            results => \@results,
           };
}

=head2 lbry_video_info($id)

Get video info for a given YouTube video ID, by scrapping the YouTube C<watch> page.

=cut

sub lbry_video_info {
    my ($self, %args) = @_;

    my $url  = $self->get_librarian_url . '/' . $args{id};
    my $hash = $self->_get_librarian_data($url) // return;

    my $info = $hash->{html}[0]{body}[0];

    #say join ' ', keys %$info;
    #use Data::Dump qw(pp);
    #pp $info->{div};
    #pp $hash;
    #exit;

    return;

    # TODO: implement it

    ref($hash) eq 'HASH' or return;

    my %video_info;

    if (ref(my $metadata = eval { $hash->{contents}{singleColumnWatchNextResults}{results}{results}{contents} }) eq 'ARRAY') {

        foreach my $entry (@$metadata) {

            ref($entry) eq 'HASH' or next;

            if (ref(my $section = eval { $entry->{slimVideoMetadataSectionRenderer}{contents} }) eq 'ARRAY') {
                foreach my $part (@$section) {
                    ref($part) eq 'HASH' or next;

                    if (my $info = $part->{slimVideoInformationRenderer}) {
                        $video_info{title} = eval { $info->{title}{runs}[0]{text} };
                    }

                    if (ref(my $buttons = $part->{slimVideoActionBarRenderer}{buttons}) eq 'ARRAY') {
                        foreach my $toggle_button (@$buttons) {

                            ref($toggle_button) eq 'HASH' or next;
                            my $button = $toggle_button->{slimMetadataToggleButtonRenderer};

                            if (    ref($button) eq 'HASH'
                                and $button->{isLike}
                                and ref(my $like_button = eval { $button->{button}{toggleButtonRenderer} }) eq 'HASH') {

                                $video_info{likeCount} = eval {
                                    _human_number_to_int($like_button->{defaultText}{accessibility}{accessibilityData}{label});
                                } // eval {
                                    (
                                     _human_number_to_int(
                                                          $like_button->{toggledText}{accessibility}{accessibilityData}{label}
                                       ) // 0
                                    ) - 1;
                                };

                                if (not defined($video_info{likeCount}) or $video_info{likeCount} <= 0) {
                                    delete $video_info{likeCount};
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    my $engagements = $hash->{engagementPanels} // return \%video_info;
    ref($engagements) eq 'ARRAY' or return \%video_info;

    foreach my $entry (@$engagements) {

        ref($entry) eq 'HASH' or next;

        if (
            ref(
                my $main_info =
                  eval { $entry->{engagementPanelSectionListRenderer}{content}{structuredDescriptionContentRenderer}{items} }
            ) eq 'ARRAY'
          ) {

            foreach my $entry (@$main_info) {

                ref($entry) eq 'HASH' or next;

                if (my $desc = $entry->{videoDescriptionHeaderRenderer}) {

                    if (ref($desc->{factoid}) eq 'ARRAY') {
                        foreach my $factoid (@{$desc->{factoid}}) {
                            ref($factoid) eq 'HASH' or next;
                            if (my $likes_info = $factoid->{sentimentFactoidRenderer}) {

                                $video_info{likeCount} //= eval {
                                    (
                                     _human_number_to_int(
                                                          $likes_info->{factoidIfLiked}{factoidRenderer}{value}{runs}[0]{text}
                                       ) // 0
                                    ) - 1;
                                };

                                if (not defined($video_info{likeCount}) or $video_info{likeCount} <= 0) {
                                    delete $video_info{likeCount};
                                }
                            }
                        }
                    }

                    $video_info{author}      //= eval { $desc->{channel}{runs}[0]{text} };
                    $video_info{publishDate} //= eval { $desc->{publishDate}{runs}[0]{text} };
                    $video_info{title}       //= eval { $desc->{title}{runs}[0]{text} };
                    $video_info{viewCount}   //= eval { _human_number_to_int($desc->{views}{runs}[0]{text} || 0) };
                }

                if (my $desc_body = $entry->{expandableVideoDescriptionBodyRenderer}) {
                    $video_info{description} //= eval { $desc_body->{descriptionBodyText}{runs}[0]{text} };
                }
            }
        }
    }

    return \%video_info;
}

sub _parse_html {
    my ($self, $html, %args) = @_;

    require HTML::TreeBuilder;

    # Workaround for invalid meta tags (occurring in description)
    $html =~ s{<meta .*?>}{}sg;

    my $tree = HTML::TreeBuilder->new_from_content($html);
    my $xml  = $tree->as_XML;

    require WWW::LbryViewer::ParseXML;
    my $hash = eval { WWW::LbryViewer::ParseXML::xml2hash($xml) } // return;

    return $hash;
}

sub _extract_search_results {
    my ($self, $hash, %args) = @_;

    my $body    = $hash->{html}[0]{body};
    my $results = $body->[0]{div};

    my @videos;
    my @next_page;

    foreach my $entry (@$results) {

        if (exists $entry->{div}) {
            foreach my $video (@{$entry->{div}}) {
                push @videos, $self->_extract_itemSection_entry($video);
            }
        }

        if (exists $entry->{'-class'} and $entry->{'-class'} eq 'pageSelector') {
            my $a    = $entry->{'a'}[-1];
            my $type = $args{type} // 'video';
            push @next_page,
              {
                type  => 'nextpage',
                token => sprintf('lbry:search:%s:%s', $type, $self->_fix_url_protocol($a->{'-href'}),),
              };
        }
    }

    push @videos, @next_page;

    return @videos;
}

sub _get_librarian_data {
    my ($self, $url, %args) = @_;

    my $content = $self->lwp_get($url)                // return;
    my $hash    = $self->_parse_html($content, %args) // return;

    return $hash;
}

=head2 lbry_search(q => $keyword, %args)

Search for videos given a keyword string (uri-escaped).

=cut

sub lbry_search {
    my ($self, %args) = @_;

    my $url = $self->get_librarian_url . "/search";

    my %params = (q => $args{q},);

    # This does not support caching
    # my $content = $self->lwp_post($url, \%params) // return;
    # my $hash    = $self->_parse_html($content, %args) // return;

    # This supports caching
    my $GET_url = $self->_append_url_args($url, %params);
    my $hash    = $self->_get_librarian_data($GET_url, %args) // return;

    my @results = $self->_extract_search_results($hash, %args);
    $self->_prepare_results_for_return(\@results, %args, url => $GET_url);
}

=head2 lbry_search_from_url($url, %args)

Returns results, given an URL.

=cut

sub lbry_search_from_url {
    my ($self, $url, %args) = @_;

    my $hash    = $self->_get_librarian_data($url, %args) // return;
    my @results = $self->_extract_search_results($hash, %args);

    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 lbry_channel_search($channel, q => $keyword, %args)

Search for videos given a keyword string (uri-escaped) from a given channel ID or username.

=cut

sub lbry_channel_search {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'search', params => {query => $args{q}});

    $hash // return;

    my @results = $self->_extract_sectionList_results($self->_find_sectionList($hash), %args, type => 'video');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 lbry_channel_uploads($channel, %args)

Latest uploads for a given channel ID or username.

=cut

sub lbry_channel_uploads {
    my ($self, $channel, %args) = @_;

    my $url = $self->get_librarian_url . "/$channel";

    my $hash    = $self->_get_librarian_data($url, %args) // return;
    my @results = $self->_extract_search_results($hash, %args);

    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 lbry_channel_info($channel, %args)

Channel info (such as title) for a given channel ID or username.

=cut

sub lbry_channel_info {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => '');
    return $hash;
}

=head2 lbry_channel_title($channel, %args)

Exact the channel title (as a string) for a given channel ID or username.

=cut

sub lbry_channel_title {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => '');
    $hash // return;
    my $header = $self->_extract_channel_header($hash, %args) // return;
    my $title  = eval { $header->{title} };
    return $title;
}

=head2 lbry_channel_id($username, %args)

Exact the channel ID (as a string) for a given channel username.

=cut

sub lbry_channel_id {
    my ($self, $username, %args) = @_;
    my ($url, $hash) = $self->_channel_data($username, %args, type => '');
    $hash // return;
    my $header = $self->_extract_channel_header($hash, %args) // return;
    my $id     = eval { $header->{channelId} }                // eval { $header->{externalId} };
    return $id;
}

=head2 lbry_channel_created_playlists($channel, %args)

Playlists created by a given channel ID or username.

=cut

sub lbry_channel_created_playlists {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'playlists', params => {view => 1});

    $hash // return;

    my @results = $self->_extract_channel_playlists($hash, %args, type => 'playlist');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 lbry_channel_all_playlists($channel, %args)

All playlists for a given channel ID or username.

=cut

sub lbry_channel_all_playlists {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'playlists');

    $hash // return;

    my @results = $self->_extract_channel_playlists($hash, %args, type => 'playlist');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 lbry_playlist_videos($playlist_id, %args)

Videos from a given playlist ID.

=cut

sub lbry_playlist_videos {
    my ($self, $playlist_id, %args) = @_;

    # TODO: implement it
}

=head2 lbry_playlist_next_page($url, $token, %args)

Load more items from a playlist, given a continuation token.

=cut

sub lbry_playlist_next_page {
    my ($self, $url, $token, %args) = @_;

    # TODO: implement it
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::LbryViewer::InitialData


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<https://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::LbryViewer::InitialData
