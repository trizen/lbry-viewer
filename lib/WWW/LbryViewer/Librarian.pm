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
        return $self->get_librarian_url() . $url;
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

sub _extract_query_url {
    my ($self, $str) = @_;

    my %params = $self->parse_query_string($str);

    if (defined($params{url})) {

        my $url = $params{url};

        if ($url !~ /^https?:/) {
            require MIME::Base64;
            $url = MIME::Base64::decode_base64($url);
        }

        return $url;
    }

    return undef;
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
                 $thumb{url} = $self->_extract_query_url($1);
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

            if ($entry->{'-class'} eq 'thumbnailWrapper' or $entry->{'-class'} eq 'relVid__thumbnailWrapper') {
                my $link = $entry->{a}[0];
                $video{videoId}         = (($link->{'-href'} // '') =~ s{^/}{}r);
                $video{videoThumbnails} = $self->_extract_thumbnails($link->{img});

                my $p = $entry->{p}[0];
                if (defined($p->{'#text'})) {
                    $video{lengthSeconds} = _extract_length_seconds($p->{'#text'}) || 0;
                }
            }

            if ($entry->{'-class'} eq 'claimMeta' or $entry->{'-class'} eq 'relVid__meta') {
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
        $video{authorId} = (($links->[1]{a}[0]{'-href'} // $links->[0]{a}[0]{'-href'} // '') =~ s{^/}{}r);

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
                $channel{authorId}         = (($link->{'-href'} // '') =~ s{^/}{}r);
                $channel{authorThumbnails} = $self->_extract_thumbnails($link->{img});
            }
        }

        $channel{author}   = $links->[0]{a}[0]{'#text'} // $links->[1]{a}[0]{'#text'};
        $channel{authorId} = (($links->[1]{a}[0]{'-href'} // $links->[0]{a}[0]{'-href'} // '') =~ s{^/}{}r);

        if (($links->[2]{'#text'} // '') =~ /([\d,.]+\s*[KMB]?)\s*followers\s*([\d,.]+\s*[KMB]?)\s*uploads/i) {
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

=head2 lbry_video_page(id => $id)

Get and parse the video page for a given video ID. Returns a HASH structure.

=cut

sub lbry_video_page {
    my ($self, %args) = @_;

    my $url  = $self->get_librarian_url . '/' . $args{id};
    my $hash = $self->_get_librarian_data($url) // return;

    my $info = $hash->{html}[0]{body}[0];

    return $info;
}

=head2 lbry_video_page_html(id => $id)

Get the video page for a given video ID as HTML.

=cut

sub lbry_video_page_html {
    my ($self, %args) = @_;

    my $url  = $self->get_librarian_url . '/' . $args{id};
    my $html = $self->lwp_get($url) // return;

    return $html;
}

=head2 lbry_video_info(id => $id)

Get video info for a given video ID.

=cut

sub lbry_video_info {
    my ($self, %args) = @_;

    my $url  = $self->get_librarian_url . '/' . $args{id};
    my $html = $self->lwp_get($url)      // return;
    my $hash = $self->_parse_html($html) // return;

    # Related videos
    my $related_vids_data = $hash->{html}[0]{body}[0]{div};

    foreach my $key (qw(videoData videoData__left videoData__right relVids)) {
        ref($related_vids_data) eq 'ARRAY' or last;
        foreach my $entry (@$related_vids_data) {
            if (ref($entry) eq 'HASH' and ($entry->{'-class'} // '') eq $key and exists($entry->{div})) {
                $related_vids_data = $entry->{'div'};
                last;
            }
        }
    }

    my @related_videos;
    if (ref($related_vids_data) eq 'ARRAY') {
        foreach my $entry (@$related_vids_data) {
            ref($entry) eq 'HASH' or next;
            exists($entry->{div}) or next;
            $entry->{'-class'} = 'video';
            my $info = $self->_extract_itemSection_entry($entry, type => 'video');
            push @related_videos, $info;
        }
    }

    my %info = (
                type           => 'video',
                extra_info     => 1,
                videoId        => $args{id},
                related_videos => \@related_videos,
               );

    # Title
    $info{title} = $hash->{html}[0]{head}[0]{title};
    $info{title} =~ s{ - Librarian\z}{};

    # View count
    if ($html =~ m{>visibility</span>\s*<p>(\d+)</p>\s*</div>}) {
        $info{viewCount} = $1;
    }

    # Likes
    if ($html =~ m{>thumb_up</span>\s*<p>(\d+)</p>\s*</div>}) {
        $info{likeCount} = $1;
    }

    # Dislikes
    if ($html =~ m{>thumb_down</span>\s*<p>(\d+)</p>\s*</div>}) {
        $info{dislikeCount} = $1;
    }

    # Rating
    {
        my $likes    = $info{likeCount}    // 0;
        my $dislikes = $info{dislikeCount} // 0;

        my $rating = 0;
        if ($likes + $dislikes > 0) {
            $rating = $likes / ($likes + $dislikes) * 5;
        }
        $info{rating} = sprintf('%.2f', $rating);
    }

    # TODO: extract the duration of the video
    #if ($html =~ m{<p class="duration">([\d:]+)</p>}) {
    #    $info{lengthSeconds} = _time_to_seconds($1);
    #}

    # Thumbnail
    if ($html =~ m{<meta name="thumbnail" content="(.*?)">}) {
        require HTML::Entities;
        my $url = HTML::Entities::decode_entities($1);
        if ($url =~ /\?(.+)/) {
            $url = $self->_extract_query_url($1);
        }
        $info{videoThumbnails} = [
                                  scalar {
                                          quality => 'medium',
                                          url     => $url,
                                          width   => 1280,
                                          height  => 720,
                                         }
                                 ];
    }

    # Published date
    # FIXME: fails when language is not English
    if ($html =~ m{<p><b>Shared (.*?)</b></p>}) {
        $info{publishDate} = _extract_published_date($1);
    }

    # Description
    if ($html =~ m{<div class="description">(.*?)</div>}s) {
        require HTML::Entities;
        my $desc = $1;
        $desc =~ s{<p>(.*?)</p>}{ $1 =~ s{<br/>}{\n}gr }sge;    # replace <br/> with 1 newline inside <p>...</p>
        $desc =~ s{<br/>}{\n\n}g;                               # replace <br/> with 2 newlines
        $desc =~ s{<hr/>}{'-' x 23}ge;                          # replace <hr/> with ----
        $desc =~ s{<.*?>}{}gs;                                  # remove HTML tags
        $desc =~ s{(?:\R\s*\R\s*)+}{\n\n}g;                     # replace 2+ newlines with 2 newlines
        $desc =~ s/^\s+//;                                      # remove leading space
        $desc =~ s/\s+\z//;                                     # remove trailing space
        $info{description} = HTML::Entities::decode_entities($desc);
    }

    # Channel name
    if ($html =~ m{<div class="videoDesc__channel">\s*<img.*?>\s*<p>\s*<b>(.*?)</b>}) {
        require HTML::Entities;
        $info{author} = HTML::Entities::decode_entities($1);
    }

    # Claim ID
    if ($html =~ m{<p class="jsonData" id="commentData">(.*?)</p>}s) {
        my $hash = $self->parse_utf8_json_string($1);
        $info{author} //= $hash->{channelName};
        $info{authorId}  = $hash->{channelName} . ':' . $hash->{channelId};
        $info{channelId} = $hash->{channelId};
        $info{claimId}   = $hash->{claimId};
    }

    return \%info;
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

    ref($results) eq 'ARRAY' or return;

    # Extract video results from a category
    if (eval { ($results->[0]{'-class'} // '') eq 'categoryBar' }) {
        shift @$results;
        $results = eval { $results->[0]{div} };
        ref($results) eq 'ARRAY' or return;
    }

    my @videos;
    my @next_page;

    foreach my $entry (@$results) {

        if (exists $entry->{div}) {
            foreach my $video (@{$entry->{div}}) {
                push @videos, $self->_extract_itemSection_entry($video);
            }
        }

        #~ if (exists $entry->{'-class'} and $entry->{'-class'} eq 'pageSelector') {
        #~ my $a    = $entry->{'a'}[-1];
        #~ my $type = $args{type} // 'video';
        #~ push @next_page,
        #~ {
        #~ type  => 'nextpage',
        #~ token => sprintf('lbry:search:%s:%s', $type, $self->_fix_url_protocol($a->{'-href'}) // ''),
        #~ };
        #~ }
    }

    push @videos, @next_page;

    return @videos;
}

sub _get_librarian_data {
    my ($self, $url, %args) = @_;

    my $html = $self->lwp_get($url)             // return;
    my $hash = $self->_parse_html($html, %args) // return;

    return $hash;
}

=head2 lbry_search(q => $keyword, %args)

Search for videos given a keyword string (uri-escaped).

=cut

sub lbry_search {
    my ($self, %args) = @_;

    my $url = $self->get_librarian_url . "/search";

    my %params = (q => $args{q});

    $self->{lwp} // $self->set_lwp_useragent;

    my $cookie_jar = $self->{lwp}->cookie_jar;
    my $domain     = $url;

    if ($domain =~ m{^https?://(.*?)/}) {
        $domain = $1;
    }

    # Set the NSFW cookie
    $cookie_jar->set_cookie(0, "nsfw", ($self->get_nsfw ? "true" : "false"), "/", $domain, undef, 0, "", 3806952123, 0, {});

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

=head2 lbry_category_videos($category_id, %args)

Returns videos from a given category ID.

=cut

sub lbry_category_videos {
    my ($self, $category_id, %args) = @_;

    my $url  = $self->_make_feed_url(defined($category_id) ? ('/$/' . $category_id) : '');
    my $hash = $self->_get_librarian_data($url, %args) // return;

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

    $channel // return;

    my $url = $self->get_librarian_url . "/$channel";

    my $hash    = $self->_get_librarian_data($url, %args) // return;
    my @results = $self->_extract_search_results($hash, %args);

    # Sort the results by published date
    @results = sort { ($b->{publishDate} // 0) <=> ($a->{publishDate} // 0) } @results;

    # Popular videos (on the current page)
    if (defined($args{sort_by}) and $args{sort_by} eq 'popular') {
        @results = sort { ($b->{viewCount} // 0) <=> ($a->{viewCount} // 0) } @results;
    }

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
