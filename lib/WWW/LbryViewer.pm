package WWW::LbryViewer;

use utf8;
use 5.016;
use warnings;

use Memoize;
use Memoize::Expire;

tie my %youtubei_cache => 'Memoize::Expire',
  LIFETIME             => 600,                 # in seconds
  NUM_USES             => 10;

memoize('_ytdl_is_available');
memoize('_info_from_ytdl');
memoize('_extract_from_ytdl');

use parent qw(
  WWW::LbryViewer::Librarian
  WWW::LbryViewer::Search
  WWW::LbryViewer::Videos
  WWW::LbryViewer::Channels
  WWW::LbryViewer::Playlists
  WWW::LbryViewer::ParseJSON
  WWW::LbryViewer::Activities
  WWW::LbryViewer::Subscriptions
  WWW::LbryViewer::PlaylistItems
  WWW::LbryViewer::CommentThreads
  WWW::LbryViewer::VideoCategories
);

use WWW::LbryViewer::Utils;

=head1 NAME

WWW::LbryViewer - A simple interface to YouTube.

=cut

our $VERSION = '0.0.3';

=head1 SYNOPSIS

    use WWW::LbryViewer;

    my $yv_obj = WWW::LbryViewer->new();
    ...

=head1 SUBROUTINES/METHODS

=cut

my %valid_options = (

    # Main options
    v          => {valid => q[],                                           default => 3},
    page       => {valid => qr/^(?!0+\z)\d+\z/,                            default => 1},
    http_proxy => {valid => qr/./,                                         default => undef},
    maxResults => {valid => [1 .. 50],                                     default => 10},
    order      => {valid => [qw(relevance rating upload_date view_count)], default => undef},
    date       => {valid => [qw(hour today week month year)],              default => undef},

    channelId => {valid => qr/^[-\w]{2,}\z/, default => undef},

    # Video only options
    videoCaption    => {valid => [qw(1 true)],           default => undef},
    videoDefinition => {valid => [qw(high standard)],    default => undef},
    videoDimension  => {valid => [qw(2d 3d)],            default => undef},
    videoDuration   => {valid => [qw(short long)],       default => undef},
    videoLicense    => {valid => [qw(creative_commons)], default => undef},
    region          => {valid => qr/^[A-Z]{2}\z/i,       default => undef},

    comments_order      => {valid => [qw(top new)],                       default => 'top'},
    subscriptions_order => {valid => [qw(alphabetical relevance unread)], default => undef},

    # Misc
    debug       => {valid => [0 .. 3],   default => 0},
    timeout     => {valid => qr/^\d+\z/, default => 10},
    config_dir  => {valid => qr/^./,     default => q{.}},
    cache_dir   => {valid => qr/^./,     default => q{.}},
    cookie_file => {valid => qr/^./,     default => undef},

    # Support for yt-dlp / youtube-dl
    ytdl     => {valid => [1, 0], default => 1},
    ytdl_cmd => {valid => qr/\w/, default => "yt-dlp"},

    # yt-dlp comment options
    ytdlp_comments     => {valid => [1, 0],             default => 0},
    ytdlp_max_comments => {valid => qr/^\d+\z/,         default => 50},
    ytdlp_max_replies  => {valid => qr/^(?:\d+|all)\z/, default => 0},

    # Booleans
    env_proxy                  => {valid => [1, 0], default => 1},
    escape_utf8                => {valid => [1, 0], default => 0},
    prefer_mp4                 => {valid => [1, 0], default => 0},
    prefer_av1                 => {valid => [1, 0], default => 0},
    prefer_invidious           => {valid => [1, 0], default => 0},
    force_fallback             => {valid => [1, 0], default => 0},
    bypass_age_gate_with_proxy => {valid => [1, 0], default => 0},

    # API/OAuth
    key           => {valid => qr/^.{15}/, default => undef},
    client_id     => {valid => qr/^.{15}/, default => undef},
    client_secret => {valid => qr/^.{15}/, default => undef},
    redirect_uri  => {valid => qr/^.{15}/, default => undef},
    access_token  => {valid => qr/^.{15}/, default => undef},
    refresh_token => {valid => qr/^.{15}/, default => undef},

    authentication_file => {valid => qr/^./, default => undef},
    api_host            => {valid => qr/\w/, default => "auto"},

    #librarian_url => {valid => qr/\w/, default => 'https://lbry.bcow.xyz'},
    #librarian_url => {valid => qr/\w/, default => 'https://lbry.vern.cc'},

#<<<
    # No input value allowed
    api_path         => {valid => q[], default => '/api/v1/'},
    www_content_type => {valid => q[], default => 'application/x-www-form-urlencoded'},
#>>>

#<<<
    # LWP user agent
    #user_agent => {valid => qr/^.{5}/, default => 'Mozilla/5.0 (iPad; CPU OS 7_1_1 like Mac OS X) AppleWebKit/537.51.2 (KHTML, like Gecko) Version/7.0 Mobile/11D201 Safari/9537.53'},
    user_agent => {valid => qr/^.{5}/, default => 'Mozilla/5.0 (Android 11; Tablet; rv:83.0) Gecko/83.0 Firefox/83.0,gzip(gfe)'},
#>>>
);

sub _our_smartmatch {
    my ($value, $arg) = @_;

    $value // return 0;

    if (not ref($arg)) {
        return ($value eq $arg);
    }

    if (ref($arg) eq ref(qr//)) {
        return scalar($value =~ $arg);
    }

    if (ref($arg) eq 'ARRAY') {
        foreach my $item (@$arg) {
            return 1 if __SUB__->($value, $item);
        }
    }

    return 0;
}

sub basic_video_info_fields {
    join(
        ',',
        qw(
          title
          videoId
          description
          descriptionHtml
          published
          publishedText
          viewCount
          likeCount
          dislikeCount
          genre
          author
          authorId
          lengthSeconds
          rating
          liveNow
          )
        );
}

sub extra_video_info_fields {
    my ($self) = @_;
    join(
        ',',
        $self->basic_video_info_fields,
        qw(
          subCountText
          captions
          isFamilyFriendly
          )
        );
}

{
    no strict 'refs';

    foreach my $key (keys %valid_options) {

        if (ref($valid_options{$key}{valid})) {

            # Create the 'set_*' subroutines
            *{__PACKAGE__ . '::set_' . $key} = sub {
                my ($self, $value) = @_;
                $self->{$key} =
                  _our_smartmatch($value, $valid_options{$key}{valid})
                  ? $value
                  : $valid_options{$key}{default};
            };
        }

        # Create the 'get_*' subroutines
        *{__PACKAGE__ . '::get_' . $key} = sub {
            my ($self) = @_;

            if (not exists $self->{$key}) {
                return ($self->{$key} = $valid_options{$key}{default});
            }

            $self->{$key};
        };
    }
}

=head2 new(%opts)

Returns a blessed object.

=cut

sub new {
    my ($class, %opts) = @_;

    my $self = bless {}, $class;

    foreach my $key (keys %valid_options) {
        if (exists $opts{$key}) {
            my $method = "set_$key";
            $self->$method(delete $opts{$key});
        }
    }

    foreach my $invalid_key (keys %opts) {
        warn "Invalid key: '${invalid_key}'";
    }

    return $self;
}

sub page_token {
    my ($self) = @_;
    my $page = $self->get_page;
    return undef if ($page == 1);
    return $page;
}

=head2 escape_string($string)

Escapes a string with URI::Escape and returns it.

=cut

sub escape_string {
    my ($self, $string) = @_;

    require URI::Escape;

    $self->get_escape_utf8
      ? URI::Escape::uri_escape_utf8($string)
      : URI::Escape::uri_escape($string);
}

=head2 set_lwp_useragent()

Initializes the LWP::UserAgent module and returns it.

=cut

sub set_lwp_useragent {
    my ($self) = @_;

    my $lwp = (
        eval { require LWP::UserAgent::Cached; 'LWP::UserAgent::Cached' }
          // do { require LWP::UserAgent; 'LWP::UserAgent' }
    );

    my $agent = $lwp->new(

        cookie_jar    => {},                      # temporary cookies
        timeout       => $self->get_timeout,
        show_progress => $self->get_debug,
        agent         => $self->get_user_agent,

        ssl_opts => {verify_hostname => 1},

        $lwp eq 'LWP::UserAgent::Cached'
        ? (
           cache_dir  => $self->get_cache_dir,
           nocache_if => sub {
               my ($response) = @_;
               my $code = $response->code;

               $code >= 300                                # do not cache any bad response
                 or $response->request->method ne 'GET'    # cache only GET requests

                 # don't cache if "cache-control" specifies "max-age=0", "no-store" or "no-cache"
                 or (($response->header('cache-control') // '') =~ /\b(?:max-age=0|no-store|no-cache)\b/)

                 # don't cache video or audio files
                 or (($response->header('content-type') // '') =~ /\b(?:video|audio)\b/);
           },

           recache_if => sub {
               my ($response, $path) = @_;
               not($response->is_fresh)                          # recache if the response expired
                 or ($response->code == 404 && -M $path > 1);    # recache any 404 response older than 1 day
           }
          )
        : (),

        env_proxy => (defined($self->get_http_proxy) ? 0 : $self->get_env_proxy),
    );

    require LWP::ConnCache;
    state $cache = LWP::ConnCache->new;
    $cache->total_capacity(undef);    # no limit

    state $accepted_encodings = do {
        require HTTP::Message;
        HTTP::Message::decodable();
    };

    $agent->ssl_opts(Timeout => $self->get_timeout);
    $agent->default_header('Accept-Encoding' => $accepted_encodings);
    $agent->conn_cache($cache);
    $agent->proxy(['http', 'https'], $self->get_http_proxy) if defined($self->get_http_proxy);

    my $cookie_file = $self->get_cookie_file;

    if (defined($cookie_file) and -f $cookie_file) {

        if ($self->get_debug) {
            say STDERR ":: Using cookies from: $cookie_file";
        }

        ## Netscape HTTP Cookies

        # Firefox extension:
        #   https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/

        # See also:
        #   https://github.com/ytdl-org/youtube-dl#how-do-i-pass-cookies-to-youtube-dl

        require HTTP::Cookies::Netscape;

        my $cookies = HTTP::Cookies::Netscape->new(
                                                   hide_cookie2 => 1,
                                                   autosave     => 1,
                                                   file         => $cookie_file,
                                                  );

        $cookies->load;
        $agent->cookie_jar($cookies);
    }
    else {

        require HTTP::Cookies;

        my $cookies = HTTP::Cookies->new();

        # Consent cookie
        $cookies->set_cookie(0, "CONSENT", "YES+cb-m.20210615-14-p0.en+FX+096",
                             "/", ".youtube.com", undef, 0, 1, '21' . join('', map { int(rand(10)) } 1 .. 8),
                             0, {});

        $agent->cookie_jar($cookies);
    }

    push @{$agent->requests_redirectable}, 'POST';
    $self->{lwp} = $agent;
    return $agent;
}

=head2 prepare_access_token()

Returns a string. used as header, with the access token.

=cut

sub prepare_access_token {
    my ($self) = @_;

    if (defined(my $auth = $self->get_access_token)) {
        return "Bearer $auth";
    }

    return;
}

sub _auth_lwp_header {
    my ($self) = @_;

    my %lwp_header;
    if (defined $self->get_access_token) {
        $lwp_header{'Authorization'} = $self->prepare_access_token;
    }

    return %lwp_header;
}

sub _warn_reponse_error {
    my ($resp, $url) = @_;
    warn sprintf("[%s] Error occurred on URL: %s\n", $resp->status_line, $url);
}

=head2 lwp_get($url, %opt)

Get and return the content for $url.

Where %opt can be:

    simple => [bool]

When the value of B<simple> is set to a true value, the
authentication header will not be set in the HTTP request.

=cut

sub lwp_get {
    my ($self, $url, %opt) = @_;

    $url || return;
    $self->{lwp} // $self->set_lwp_useragent();

    if ($url =~ m{^//}) {
        $url = 'https:' . $url;
    }

    my %lwp_header = ($opt{simple} ? () : $self->_auth_lwp_header);

    if ($url !~ /^https?:/) {    # maybe it's base64 encoded?

        if ($self->get_debug) {
            say STDERR ":: URL without protocol: $url";
        }

        require MIME::Base64;
        $url = MIME::Base64::decode_base64($url);
    }

    my $response = do {
        my $r;

        if ($url =~ m{^https?://[^/]+\.onion/}) {    # onion URL

            if (not defined($self->get_http_proxy)) {    # no proxy defined
                if ($self->get_env_proxy and (defined($ENV{HTTP_PROXY}) or defined($ENV{HTTPS_PROXY}))) {
                    ## ok -- LWP::UserAgent will use proxy defined in ENV
                }
                else {
                    say ":: Setting proxy for onion websites..." if $self->get_debug;
                    $self->{lwp}->proxy(['http', 'https'], 'socks://localhost:9050');
                    $r = $self->{lwp}->get($url, %lwp_header);
                    $self->{lwp}->proxy(['http', 'https'], undef);
                }
            }
        }

        $r // $self->{lwp}->get($url, %lwp_header);
    };

    if ($response->is_success) {
        return $response->decoded_content;
    }

    $opt{depth} ||= 0;

    # Try again on 500+ HTTP errors
    if (    $opt{depth} < 1
        and $response->code() >= 500
        and $response->status_line() =~ /(?:Temporary|Server) Error|Timeout|Service Unavailable/i) {
        return $self->lwp_get($url, %opt, depth => $opt{depth} + 1);
    }

    # Too many errors. Pick another Librarian instance.
    if ($url !~ m{(?:\byoutube\.com/|\bi\.ytimg\.com/)}) {
        ## TODO
    }

    _warn_reponse_error($response, $url);
    return;
}

=head2 lwp_post($url, [@args])

Post and return the content for $url.

=cut

sub lwp_post {
    my ($self, $url, @args) = @_;

    $self->{lwp} // $self->set_lwp_useragent();

    my $response = $self->{lwp}->post($url, @args);

    if ($response->is_success) {
        return $response->decoded_content;
    }
    else {
        _warn_reponse_error($response, $url);
    }

    return;
}

=head2 lwp_mirror($url, $output_file)

Downloads the $url into $output_file. Returns true on success.

=cut

sub lwp_mirror {
    my ($self, $url, $output_file) = @_;
    $self->{lwp} // $self->set_lwp_useragent();
    $self->{lwp}->mirror($url, $output_file);
}

sub _get_results {
    my ($self, $url, %opt) = @_;

    return
      scalar {
              url     => $url,
              results => $self->parse_json_string($self->lwp_get($url, %opt)),
             };
}

=head2 list_to_url_arguments(\%options)

Returns a valid string of arguments, with defined values.

=cut

sub list_to_url_arguments {
    my ($self, %args) = @_;
    join(q{&}, map { "$_=$args{$_}" } grep { defined $args{$_} } sort keys %args);
}

sub _append_url_args {
    my ($self, $url, %args) = @_;
    %args
      ? ($url . ($url =~ /\?/ ? '&' : '?') . $self->list_to_url_arguments(%args))
      : $url;
}

sub get_invidious_instances {
    my ($self) = @_;

    require File::Spec;
    my $instances_file = File::Spec->catfile($self->get_config_dir, 'instances.json');

    # Get the "instances.json" file when the local copy is too old or non-existent
    if ((not -e $instances_file) or (-M _) > 1 / 24) {

        require LWP::UserAgent;

        my $lwp = LWP::UserAgent->new(timeout => $self->get_timeout);
        $lwp->show_progress(1) if $self->get_debug;
        my $resp = $lwp->get("https://api.invidious.io/instances.json");

        $resp->is_success() or return;

        my $json = $resp->decoded_content() || return;
        open(my $fh, '>', $instances_file) or return;
        print $fh $json;
        close $fh;
    }

    open(my $fh, '<', $instances_file) or return;

    my $json_string = do {
        local $/;
        <$fh>;
    };

    $self->parse_json_string($json_string);
}

sub get_librarian_instances {
    my ($self, %args) = @_;

    my @instances = qw(
      lbry.bcow.xyz
      librarian.pussthecat.org
      lbry.mutahar.rocks
      librarian.esmailelbob.xyz
      lbry.vern.cc
    );

    return @instances;
}

sub _find_working_instance {
    my ($self, $candidates) = @_;

    require List::Util;
    state $yv_utils = WWW::LbryViewer::Utils->new();

    foreach my $instance (List::Util::shuffle(@$candidates)) {

        my $uri = "https://$instance";
        local $self->{api_host} = $uri;
        my $results = $self->search_videos('test');

        if ($yv_utils->has_entries($results)) {
            return $uri;
        }
    }

    return;
}

sub pick_random_instance {
    my ($self) = @_;

    my @candidates = $self->get_librarian_instances();

    if (defined(my $instance = $self->_find_working_instance(\@candidates))) {
        return $instance;
    }

    $candidates[rand @candidates];
}

sub pick_and_set_random_instance {
    my ($self) = @_;

    # For now, pick the official one, as it is more likely to work
    return $self->set_api_host("https://lbry.bcow.xyz");

    # Get the list of invidious instances
    # my @instances = $self->get_librarian_instances();

    # Select a random instance
    #my $instance = $instances[rand @instances];

    #my $instance = $instances[0];
    my $instance = $self->pick_random_instance();

    # Set the instance
    $self->set_api_host($instance);
}

sub get_librarian_url {
    my ($self) = @_;

    my $host = $self->get_api_host;

    # Remove whitespace (if any)
    $host =~ s/^\s+//;
    $host =~ s/\s+\z//;

    $host =~ s{/+\z}{};    # remove trailing '/'

    if ($host =~ /\w\.\w/ and $host !~ m{^\w+://}) {    # no protocol specified

        my $protocol = 'https://';                      # default to HTTPS

        if ($host =~ m{^[^/]+\.onion\z}) {              # onion URL
            $protocol = 'http://';                      # default to HTTP
        }

        $host = $protocol . $host;
    }

    # Pick a random instance when `--instance=auto`
    if ($host eq 'auto') {

        if (defined($self->pick_and_set_random_instance())) {
            $host = $self->get_api_host();
            print STDERR ":: Changed the instance to: $host\n" if $self->get_debug;
        }
        else {
            $host = "https://lbry.bcow.xyz";
            $self->set_api_host($host);
            print STDERR ":: Failed to change the instance. Using: $host\n" if $self->get_debug;
        }
    }

    return $host;
}

sub _simple_feeds_url {
    my ($self, $path, %args) = @_;
    $self->get_api_url . $path . '?' . $self->list_to_url_arguments(key => $self->get_key, %args);
}

=head2 default_arguments(%args)

Merge the default arguments with %args and concatenate them together.

=cut

sub default_arguments {
    my ($self, %args) = @_;

    my %defaults = (

        #key         => $self->get_key,
        #part        => 'snippet',
        #prettyPrint => 'false',
        #maxResults  => $self->get_maxResults,
        %args,
                   );

    $self->list_to_url_arguments(%defaults);
}

sub _make_feed_url {
    my ($self, $path, %args) = @_;

    my $extra_args = $self->default_arguments(%args);
    my $url        = $self->get_api_url . $path;

    if ($extra_args) {
        $url .= '?' . $extra_args;
    }

    return $url;
}

sub _ytdl_is_available {
    my ($self) = @_;
    ($self->proxy_stdout($self->get_ytdl_cmd(), '--version') // '') =~ /\d/;
}

sub _info_from_ytdl {
    my ($self, $videoID) = @_;

    $self->_ytdl_is_available() || return;

    my @ytdl_cmd = ($self->get_ytdl_cmd(), '--all-formats', '--dump-single-json');

    my $cookie_file = $self->get_cookie_file;

    if (defined($cookie_file) and -f $cookie_file) {
        push @ytdl_cmd, '--cookies', quotemeta($cookie_file);
    }

    my $json = $self->proxy_stdout(@ytdl_cmd, quotemeta("https://odysee.com/" . $videoID));
    my $ref  = $self->parse_json_string($json // return);

    if ($self->get_debug >= 3) {
        require Data::Dump;
        Data::Dump::pp($ref);
    }

    return $ref;
}

sub _extract_from_ytdl {
    my ($self, $videoID) = @_;

    my $ref = $self->_info_from_ytdl($videoID) // return;

    my @formats;

    if (ref($ref) eq 'HASH' and exists($ref->{formats}) and ref($ref->{formats}) eq 'ARRAY') {
        foreach my $format (@{$ref->{formats}}) {
            if (exists($format->{format_id}) and exists($format->{url})) {

                my $entry = {
                             itag => $format->{format_id},
                             url  => $format->{url},
                             type => ((($format->{format} // '') =~ /audio only/i) ? 'audio/' : 'video/') . $format->{ext},
                            };

                push @formats, $entry;
            }
        }
    }

    if (!@formats and defined($ref->{url})) {
        push @formats,
          scalar {
                  itag => 'b',
                  type => 'video/mp4',
                  url  => $ref->{url},
                 };
    }

    return @formats;
}

sub _fallback_extract_urls {
    my ($self, $videoID) = @_;

    my @formats;

    # Use youtube-dl
    if ($self->get_ytdl and $self->_ytdl_is_available) {

        if ($self->get_debug) {
            my $cmd = $self->get_ytdl_cmd;
            say STDERR ":: Using $cmd to extract the streaming URLs...";
        }

        push @formats, $self->_extract_from_ytdl($videoID);

        if ($self->get_debug) {
            my $count = scalar(@formats);
            my $cmd   = $self->get_ytdl_cmd;
            say STDERR ":: $cmd: found $count streaming URLs...";
        }

        @formats && return @formats;
    }

    return @formats;
}

=head2 parse_query_string($string, multi => [0,1])

Parse a query string and return a data structure back.

When the B<multi> option is set to a true value, the function will store multiple values for a given key.

Returns back a list of key-value pairs.

=cut

sub parse_query_string {
    my ($self, $str, %opt) = @_;

    if (not defined($str)) {
        return;
    }

    require URI::Escape;

    my @pairs;
    foreach my $statement (split(/,/, $str)) {
        foreach my $pair (split(/&/, $statement)) {
            push @pairs, $pair;
        }
    }

    my %result;

    foreach my $pair (@pairs) {
        my ($key, $value) = split(/=/, $pair, 2);

        if (not defined($value) or $value eq '') {
            next;
        }

        $value = URI::Escape::uri_unescape($value =~ tr/+/ /r);

        if ($opt{multi}) {
            push @{$result{$key}}, $value;
        }
        else {
            $result{$key} = $value;
        }
    }

    return %result;
}

sub _group_keys_with_values {
    my ($self, %data) = @_;

    my @hashes;

    foreach my $key (keys %data) {
        foreach my $i (0 .. $#{$data{$key}}) {
            $hashes[$i]{$key} = $data{$key}[$i];
        }
    }

    return @hashes;
}

sub _check_streaming_urls {
    my ($self, $videoID, $results) = @_;

    foreach my $video (@$results) {

        if (   exists $video->{s}
            or exists $video->{signatureCipher}
            or exists $video->{cipher}) {    # has an encrypted signature :(

            if ($self->get_debug) {
                say STDERR ":: Detected an encrypted signature...";
            }

            my @formats = $self->_fallback_extract_urls($videoID);

            foreach my $format (@formats) {
                foreach my $ref (@$results) {
                    if (defined($ref->{itag}) and ($ref->{itag} eq $format->{itag})) {
                        $ref->{url} = $format->{url};
                        last;
                    }
                }
            }

            last;
        }
    }

    foreach my $video (@$results) {
        if (exists $video->{mimeType}) {
            $video->{type} = $video->{mimeType};
        }
    }

    return 1;
}

sub _old_extract_streaming_urls {
    my ($self, $info, $videoID) = @_;

    if ($self->get_debug) {
        say STDERR ":: Using `url_encoded_fmt_stream_map` to extract the streaming URLs...";
    }

    my %stream_map    = $self->parse_query_string($info->{url_encoded_fmt_stream_map}, multi => 1);
    my %adaptive_fmts = $self->parse_query_string($info->{adaptive_fmts},              multi => 1);

    if ($self->get_debug >= 2) {
        require Data::Dump;
        Data::Dump::pp(\%stream_map);
        Data::Dump::pp(\%adaptive_fmts);
    }

    my @results;

    push @results, $self->_group_keys_with_values(%stream_map);
    push @results, $self->_group_keys_with_values(%adaptive_fmts);

    $self->_check_streaming_urls($videoID, \@results);

    if ($info->{livestream} or $info->{live_playback}) {

        if ($self->get_debug) {
            say STDERR ":: Live stream detected...";
        }

        if (my @formats = $self->_fallback_extract_urls($videoID)) {
            @results = @formats;
        }
        elsif (exists $info->{hlsvp}) {
            push @results,
              {
                itag => 38,
                type => 'video/ts',
                url  => $info->{hlsvp},
              };
        }
    }

    return @results;
}

sub _extract_streaming_urls {
    my ($self, $json, $videoID) = @_;

    if ($self->get_debug) {
        say STDERR ":: Using `player_response` to extract the streaming URLs...";
    }

    if ($self->get_debug >= 2) {
        require Data::Dump;
        Data::Dump::pp($json);
    }

    ref($json) eq 'HASH' or return;

    my @results;
    if (exists $json->{streamingData}) {

        my $streamingData = $json->{streamingData};

        if (defined $streamingData->{dashManifestUrl}) {
            say STDERR ":: Contains DASH manifest URL" if $self->get_debug;
            ##return;
        }

        if (exists $streamingData->{adaptiveFormats}) {
            push @results, @{$streamingData->{adaptiveFormats}};
        }

        if (exists $streamingData->{formats}) {
            push @results, @{$streamingData->{formats}};
        }
    }

    $self->_check_streaming_urls($videoID, \@results);

    # Keep only streams with contentLength > 0.
    @results = grep { $_->{itag} == 22 or (exists($_->{contentLength}) and $_->{contentLength} > 0) } @results;

    # Filter out streams with "dur=0.000"
    @results = grep { $_->{url} !~ /\bdur=0\.000\b/ } grep { defined($_->{url}) } @results;

    # Detect livestream
    if (!@results and exists($json->{streamingData}) and exists($json->{streamingData}{hlsManifestUrl})) {

        if ($self->get_debug) {
            say STDERR ":: Live stream detected...";
        }

        @results = $self->_fallback_extract_urls($videoID);

        if (!@results) {
            push @results,
              {
                itag => 38,
                type => "video/ts",
                url  => $json->{streamingData}{hlsManifestUrl},
              };
        }
    }

    return @results;
}

sub _make_translated_captions {
    my ($self, $caption_urls) = @_;

    my @languages = qw(
      af am ar az be bg bn bs ca ceb co cs cy da de el en eo es et eu fa fi fil
      fr fy ga gd gl gu ha haw hi hmn hr ht hu hy id ig is it iw ja jv ka kk km
      kn ko ku ky la lb lo lt lv mg mi mk ml mn mr ms mt my ne nl no ny or pa pl
      ps pt ro ru rw sd si sk sl sm sn so sq sr st su sv sw ta te tg th tk tr tt
      ug uk ur uz vi xh yi yo zh-Hans zh-Hant zu
    );

    my %trans_languages = map { $_->{languageCode} => 1 } @$caption_urls;
    @languages = grep { not exists $trans_languages{$_} } @languages;

    my @asr;
    foreach my $caption (@$caption_urls) {
        foreach my $lang_code (@languages) {
            my %caption_copy = %$caption;
            $caption_copy{languageCode} = $lang_code;
            $caption_copy{baseUrl}      = $caption_copy{baseUrl} . "&tlang=$lang_code";
            push @asr, \%caption_copy;
        }
    }

    return @asr;
}

sub _fallback_extract_captions {
    my ($self, $videoID) = @_;

    return;    # TODO: implement it (do LBRY videos have CC?)

    if ($self->get_debug) {
        my $cmd = $self->get_ytdl_cmd;
        say STDERR ":: Extracting closed-caption URLs with $cmd";
    }

    my $ytdl_info = $self->_info_from_ytdl($videoID);

    my @caption_urls;

    if (defined($ytdl_info) and ref($ytdl_info) eq 'HASH') {

        my $has_subtitles = 0;

        foreach my $key (qw(subtitles automatic_captions)) {

            my $ccaps = $ytdl_info->{$key} // next;

            ref($ccaps) eq 'HASH' or next;

            foreach my $lang_code (sort keys %$ccaps) {

                my ($caption_info) = grep { $_->{ext} eq 'srv1' } @{$ccaps->{$lang_code}};

                if (defined($caption_info) and ref($caption_info) eq 'HASH' and defined($caption_info->{url})) {

                    push @caption_urls,
                      scalar {
                              kind         => ($key eq 'automatic_captions' ? 'asr' : ''),
                              languageCode => $lang_code,
                              baseUrl      => $caption_info->{url},
                             };

                    if ($key eq 'subtitles') {
                        $has_subtitles = 1;
                    }
                }
            }

            last if $has_subtitles;
        }

        # Auto-translated captions
        if ($has_subtitles) {

            if ($self->get_debug) {
                say STDERR ":: Generating translated closed-caption URLs...";
            }

            push @caption_urls, $self->_make_translated_captions(\@caption_urls);
        }
    }

    return @caption_urls;
}

=head2 get_streaming_urls($videoID)

Returns a list of streaming URLs for a videoID.
({itag=>..., url=>...}, {itag=>..., url=>....}, ...)

=cut

sub get_streaming_urls {
    my ($self, $videoID) = @_;

    my @caption_urls;
    my @streaming_urls = $self->_fallback_extract_urls($videoID);

    if (!@caption_urls) {
        push @caption_urls, $self->_fallback_extract_captions($videoID);
    }

    if ($self->get_debug) {
        my $count = scalar(@streaming_urls);
        say STDERR ":: Found $count streaming URLs...";
    }

    # Return the LBRY URL when there are no streaming URLs
    if (!@streaming_urls) {
        push @streaming_urls,
          {
            itag => 'b',
            type => "video/mp4",
            url  => "https://odysee.com/$videoID",
          };
    }

    if ($self->get_debug >= 2) {
        require Data::Dump;
        Data::Dump::pp(\@streaming_urls);
        Data::Dump::pp(\@caption_urls);
    }

    return (\@streaming_urls, \@caption_urls);
}

sub _request {
    my ($self, $req) = @_;

    $self->{lwp} // $self->set_lwp_useragent();

    my $res = $self->{lwp}->request($req);

    if ($res->is_success) {
        return $res->decoded_content;
    }
    else {
        warn 'Request error: ' . $res->status_line();
    }

    return;
}

sub _prepare_request {
    my ($self, $req, $length) = @_;

    $req->header('Content-Length' => $length) if ($length);

    if (defined $self->get_access_token) {
        $req->header('Authorization' => $self->prepare_access_token);
    }

    return 1;
}

sub _save {
    my ($self, $method, $uri, $content) = @_;

    require HTTP::Request;
    my $req = HTTP::Request->new($method => $uri);
    $req->content_type('application/json; charset=UTF-8');
    $self->_prepare_request($req, length($content));
    $req->content($content);

    $self->_request($req);
}

sub post_as_json {
    my ($self, $url, $ref) = @_;
    my $json_str = $self->make_json_string($ref);
    $self->_save('POST', $url, $json_str);
}

sub next_page_with_token {
    my ($self, $url, $token) = @_;

    if (ref($token) eq 'CODE') {
        return $token->();
    }

    if ($token =~ /^ytdlp:comments:(.*?):(\d+):(.*?):(.*)/) {
        my ($video_id, $page, $prev_root_comment_id, $prev_comment_id) = ($1, $2, $3, $4);
        return $self->comments_from_ytdlp($video_id, $page, $prev_root_comment_id, $prev_comment_id);
    }

    if ($token =~ /^yt(search|browse):(\w+):(.*)/) {
        if ($1 eq 'browse') {
            return $self->yt_browse_next_page($url, $3, type => $2, url => $url);
        }
        else {
            return $self->yt_search_next_page($url, $3, type => $2, url => $url);
        }
    }

    if ($token =~ m{^lbry:search:(\w+):(.+)}) {
        my $type = $1;
        my $url  = $2;
        return $self->lbry_search_from_url($url, type => $type);
    }

    if ($token =~ /^ytplaylist:(\w+):(.*)/) {
        return $self->yt_playlist_next_page($url, $2, type => $1, url => $url);
    }

    if ($url =~ m{^https://m\.youtube\.com}) {
        return
          scalar {
                  url     => $url,
                  results => [],
                 };
    }

    if (not $url =~ s{[?&]continuation=\K([^&]+)}{$token}) {
        $url = $self->_append_url_args($url, continuation => $token);
    }

    my $res = $self->_get_results($url);
    $res->{url} = $url;
    return $res;
}

sub next_page {
    my ($self, $url, $token) = @_;

    if ($token) {
        return $self->next_page_with_token($url, $token);
    }

    if ($url =~ m{^https://m\.youtube\.com}) {
        return
          scalar {
                  url     => $url,
                  results => [],
                 };
    }

    if (not $url =~ s{[?&]page=\K(\d+)}{$1+1}e) {
        $url = $self->_append_url_args($url, page => 2);
    }

    my $res = $self->_get_results($url);
    $res->{url} = $url;
    return $res;
}

# SUBROUTINE FACTORY
{
    no strict 'refs';

    # Create proxy_{exec,system} subroutines
    foreach my $name ('exec', 'system', 'stdout') {
        *{__PACKAGE__ . '::proxy_' . $name} = sub {
            my ($self, @args) = @_;

            $self->{lwp} // $self->set_lwp_useragent();

            local $ENV{http_proxy}  = $self->{lwp}->proxy('http');
            local $ENV{https_proxy} = $self->{lwp}->proxy('https');

            local $ENV{HTTP_PROXY}  = $self->{lwp}->proxy('http');
            local $ENV{HTTPS_PROXY} = $self->{lwp}->proxy('https');

            local $" = " ";

                $name eq 'exec'   ? exec(@args)
              : $name eq 'system' ? system(@args)
              : $name eq 'stdout' ? qx(@args)
              :                     ();
        };
    }
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>

=head1 SEE ALSO

https://developers.google.com/youtube/v3/docs/

=head1 LICENSE AND COPYRIGHT

Copyright 2012-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<https://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;    # End of WWW::LbryViewer

__END__
