#!/usr/bin/perl

use strict;
use warnings;
use 5.014;
use utf8;

use lib './lib';
use URI::Escape qw( uri_escape );
use Template ();

use File::Basename qw( basename );
use File::Path qw( mkpath );
use File::Spec ();
use Path::Tiny qw/ path /;

use Parallel::ForkManager::Segmented   ();
use HTML::Widgets::NavMenu::HeaderRole ();
use HTML::Widgets::NavMenu::EscapeHtml qw( escape_html );
use MyNavData ();

sub _render_leading_path_component
{
    my $component  = shift;
    my $title      = $component->title();
    my $title_attr = defined($title) ? " title=\"$title\"" : "";
    return
          "<a href=\""
        . escape_html( $component->direct_url() )
        . "\"$title_attr>"
        . $component->label() . "</a>";
}

# use MyNavLinks ();

my $LATEMP_SERVER = "perl_begin";
my $template      = Template->new(
    {
        INCLUDE_PATH => [ ".", "./lib", ],
        POST_CHOMP   => 1,
        RELATIVE     => 1,
        ENCODING     => 'utf8',
    }
);

sub cpan_mod
{
    my %args = @_;
    return qq#<a href="http://metacpan.org/module/$args{m}">$args{body}</a>#;
}

sub cpan_dist
{
    my %args = %{ shift() };
    return qq#<a href="http://metacpan.org/release/$args{d}">$args{body}</a>#;
}

sub retrieved_slurp
{
    return slurp( "lib/retrieved-html-parts/" . shift );
}

sub slurp
{
    return path(shift)->slurp_utf8;
}

my @DEST = ( File::Spec->curdir(), "dest", );
my $vars = +{
    wiki_link => sub {
        my %args = %{ shift() // {} };
        return qq#http://perl.net.au/wiki/Beginners#
            . ( $args{url} ? '/' . $args{url} : '' );
    },
    cpan_self_mod => sub {
        my %args = %{ shift() };
        return cpan_mod( %args, body => $args{m} );
    },
    cpan_b_self_dist => sub {
        my %args = %{ shift() };
        return cpan_dist( { %args, body => "<b>$args{d}</b>", } );
    },
    irc_channel => sub {
        my %args    = %{ shift() };
        my $net     = $args{net};
        my $chan    = $args{chan};
        my %servers = (
            'freenode' => "irc.freenode.net",
            'efnet'    => "irc.Prison.NET",
            'oftc'     => "irc.oftc.net",
            'undernet' => "us.undernet.org",
            'ircnet'   => "ircnet.demon.co.uk",
        );
        if ( !exists( $servers{$net} ) )
        {
            die "Unknown network!";
        }
        return
              "<a href=\"irc://"
            . $servers{$net}
            . "/%23$chan\"><code>#$chan</code></a>";
    },
    cpan_self_dist => sub {
        my %args = %{ shift() };
        return cpan_dist( { %args, body => $args{d} } );
    },
    retrieved_slurp => \&retrieved_slurp,
    p4n_slurp       => sub {
        my $idx = shift;
        return path(
            "lib/tutorials/perl-for-newbies/lect$idx-all-in-one/index.html")
            ->slurp_utf8() =~ s{.*<body[^>]*>}{}mrs =~ s{< / body >.*}{}mrsx;
    },
};

my $proc = sub {
    my $result   = shift;
    my $basename = basename($result);
    my @fn       = split m#/#, $result;
    my @fn_nav   = @fn;
    if ( $fn_nav[-1] =~ m#\Aindex\.x?html\z# )
    {
        $fn_nav[-1] = '';
    }
    my $base_path =
        ( '../' x ( scalar(@fn) - 1 ) );
    my $fn2     = join( '/', @fn_nav ) || '/';
    my $nav_bar = HTML::Widgets::NavMenu::HeaderRole->new(
        'path_info'    => $fn2,
        'current_host' => $LATEMP_SERVER,
        MyNavData::get_params(),
        'ul_classes'     => [ "navbarmain", ("navbarnested") x 10 ],
        'no_leading_dot' => 1,
    );

    my $rendered_results = $nav_bar->render();

    my $nav_links_obj = $rendered_results->{nav_links_obj};

    my $nav_html = $rendered_results->{html};

=begin removed
            my $nav_links = $rendered_results->{nav_links};
            my $nav_links_renderer = MyNavLinks->new(
                'nav_links'     => $nav_links,
                'nav_links_obj' => $nav_links_obj,
                'root'          => $base_path,
            );
            my $with_accesskey = '';
            my @params;
            if ( $with_accesskey ne "" )
            {
                push @params, ( 'with_accesskey' => $with_accesskey );
            }
            my $text = $nav_links_renderer->get_total_html(@params);
=cut

    my $t2 = '';

    {
        my @keys = ( sort { $a cmp $b } keys(%$nav_links_obj) );
    LINKS:
        foreach my $key (@keys)
        {
            if ( ( $key eq 'top' ) or ( $key eq 'up' ) )
            {
                next LINKS;
            }
            my $val        = $nav_links_obj->{$key};
            my $url        = escape_html( $val->direct_url() );
            my $title      = $val->title();
            my $title_attr = defined($title) ? " title=\"$title\"" : "";
            $t2 .= "<link rel=\"$key\" href=\"$url\"$title_attr />\n";
        }
    }

    my $leading_path = $rendered_results->{leading_path};

    my $leading_path_string = join( " → ",
        ( map { _render_leading_path_component($_) } @$leading_path ) );
    my $share_link = escape_html(
        uri_escape(
            MyNavData::get_hosts()->{ $nav_bar->current_host() }->{'base_url'}
                . $nav_bar->path_info()
        )
    );

    mkpath( File::Spec->catdir( @DEST, @fn[ 0 .. $#fn - 1 ] ) );
    $vars->{base_path}           = $base_path;
    $vars->{leading_path_string} = $leading_path_string;
    $vars->{nav_links}           = $t2;
    $vars->{nav_menu_html}       = join( '', @$nav_html );
    $vars->{share_link}          = $share_link;
    $vars->{slurp_bad_elems}     = sub {
        return path("lib/docbook/5/rendered/bad-elements.xhtml")->slurp_utf8()
            =~ s{\$\(ROOT\)}{$base_path}gr;
    };
    $template->process(
        "src/$result.tt2", $vars,
        File::Spec->catfile( @DEST, @fn, ),
        binmode => ':utf8',
    ) or die $template->error();

=begin removed

        elsif (
            $basename !~ /~\z/
            && ( !($basename =~ /\A\./ && $basename =~ /\.swp\z/) )
            && ($basename ne 'process.pl')
        )
        {
            copy($result->path,
                File::Spec->catfile(@DEST,
                    @{$result->dir_components()}, $basename),
            );
        }
=end removed

=cut

};
my @tt = path("lib/make/tt2.txt")->lines_raw;
chomp @tt;
Parallel::ForkManager::Segmented->new->run(
    {
        items        => \@tt,
        nproc        => 4,
        batch_size   => 8,
        process_item => $proc,
    }
);
