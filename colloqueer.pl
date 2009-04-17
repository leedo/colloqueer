#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Template;
use DateTime;
use MIME::Base64 qw/encode_base64/;
use Encode;
use IPC::Open2;
use Gtk2 -init;
use Gtk2::Gdk::Keysyms;
use Gtk2::WebKit;
use Glib qw/TRUE FALSE/;
use XML::LibXML;
use XML::LibXSLT;
use POE qw/Component::IRC::State/;
use POE::Kernel { loop => 'Glib' };
use YAML::Any;
use Data::Dumper;

open my $config_fh, '<', 'config.yaml';

my $config = Load(join "\n", <$config_fh>);
print Dumper $config;

my $url_re = q{\b(s?https?|ftp|file|gopher|s?news|telnet|mailbox):} .
             q{(//[-A-Z0-9_.]+:\d*)?} .
             q{[-A-Z0-9_=?\#:\$\@~\`%&*+|\/.,;\240]+};

my $irc = POE::Component::IRC->spawn( 
  nick => $config->{nick},
  port => $config->{server}{port},
  ircname => $config->{ircname},
  username => $config->{server}{username},
  password => $config->{server}{password},
  server => $config->{server}{host},
) or die $!;

POE::Session->create(
  package_states => [
    main => [ qw/_start irc_001 irc_public/ ],
  ],
  heap => {
    parser => XML::LibXML->new(),
    xslt => XML::LibXSLT->new(),
    irc => $irc,
    style => 'Buttesfire',
    nick => $config->{nick},
    channels => { map {$_ => {}} @{$config->{channels}} },
  },
);

$poe_kernel->run();
exit 0;

sub irc_001 {
  my ($heap, $sender) = @_[HEAP, SENDER];
  my $irc = $sender->get_heap();
  for (keys %{$heap->{channels}}) {
    $irc->yield( join => $_);
    setup_tab($heap, $_);
  }
}

sub setup_tab {
  my ($heap, $channel) = @_;
  my $paned = Gtk2::VPaned->new;
  my $frame = Gtk2::Frame->new;
  my $wv = Gtk2::WebKit::WebView->new;
  my $entry = Gtk2::Entry->new;
  $heap->{channels}{$channel}{msgs} = [];
  $entry->signal_connect("key_press_event", sub {
    my ($widget, $event) = @_;
    if ($event->keyval == $Gtk2::Gdk::Keysyms{Return}) {
      if ($widget->get_text =~ /^\/(.+)/) {
        handle_command($heap, $1);
      }
      else {
        $irc->yield(privmsg => $channel => $widget->get_text);
        push @{$heap->{channels}{$channel}{msgs}}, {
          nick  => $heap->{nick},
          text  => irc2html($widget->get_text),
          date  => DateTime->now,
          id    => encode_base64($heap->{nick}.time)
        };
        $widget->set_text('');
        refresh_channel($channel, $heap);
      }
    }
  });
  $frame->add($wv);
  $paned->pack1($frame, TRUE, FALSE);
  $paned->pack2($entry, FALSE, FALSE);
  $heap->{notebook}->append_page($paned, $channel);
  $heap->{channels}{$channel}{view} = $wv;
  $heap->{main_window}->show_all;
}

sub handle_command {
  my ($heap, $command) = @_;
  if ($command =~ /^join (.+)/) {
    $heap->{irc}->yield( join => $1);
    setup_tab($heap, $1);
  }
}

sub irc_public {
  my ($heap, $sender, $who, $where, $what) = @_[HEAP, SENDER, ARG0 .. ARG2];
  my $from = ( split /!/, $who )[0];
  my $channel = $where->[0];
  return unless exists $heap->{channels}{$channel};

  push @{$heap->{channels}{$channel}{msgs}}, {
    nick  => $from,
    text  => irc2html($what),
    date  => DateTime->now,
    id    => encode_base64($from.time)
  };
  refresh_channel($channel, $heap);
}

sub refresh_channel {
  my ($channel, $heap) = @_;
  my (@msg_out, @buff);
  my @msg_in = @{$heap->{channels}{$channel}{msgs}};
  my $lastnick = $msg_in[0]->{nick};
  for my $index (0 .. $#msg_in) {
    my $msg = $msg_in[$index];
    $msg->{id} =~ s/=*\n//; # strip trailing mime crud
    if ($msg->{nick} ne $lastnick) {
      push @msg_out, format_messages($heap, @buff);
      @buff = ();
    }
    push @buff, $msg;
    $lastnick = $msg->{nick};
  }
  push @msg_out, format_messages($heap, @buff);
  $heap->{tt}->process('base.html', {msgs => \@msg_out}, \(my $html)); 
  $heap->{channels}{$channel}{view}->load_html_string($html, '/');
}

sub format_messages {
  my ($heap, @msgs) = @_;
  my $from = $msgs[0]->{nick};
  $heap->{tt}->process('message.xml', {
    user  => $from,
    msgs  => \@msgs,
    self  => $from eq $heap->{nick} ? 1 : 0,
  }, \(my $message)) or die $!;
  my $doc = $heap->{parser}->parse_string($message,{encoding => 'utf8'});
  my $results = $heap->{style_doc}->transform($doc,
    XML::LibXSLT::xpath_to_string(
      consecutiveMessage => 'no',
      fromEnvelope => 'yes',
      bulkTransform => "yes",
  ));
  $message = $heap->{style_doc}->output_string($results);
  $message =~ s/<span[^\/>]*\/>//gi; # strip empty spans
  return decode_utf8($message);
}

sub irc2html {
  my $string = shift;
  my $pid = open2 my $out, my $in, "ruby $FindBin::Bin/irc2html.rb";
  print $in $string;
  close $in;
  $string = <$out>;
  $string =~ s/\s{2}/ &#160;/g;
  $string =~ s@($url_re+)@<a href="$1">$1</a>@gi;
  close $out;
  chomp $string;
  wait;
  return $string;
}

sub _start {
  my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];

  $heap->{share_dir} = "$FindBin::Bin/share";
  $heap->{theme_dir} = $heap->{share_dir} . '/styles/'
    . $heap->{style} . ".colloquyStyle/Contents/Resources";

  $heap->{tt} = Template->new(
    ENCODING => 'utf8',
    INCLUDE_PATH => [$heap->{share_dir}, $heap->{theme_dir}]);
  
  $heap->{style_doc} = $heap->{xslt}->parse_stylesheet(
    $heap->{parser}->parse_file($heap->{theme_dir}."/main.xsl"));

  $heap->{tt}->process('base.html',undef,\(my $html))
    or die $heap->{tt}->error;

  $heap->{main_window} = Gtk2::Window->new('toplevel');
  $heap->{main_window}->set_default_size(500,400);
  $heap->{main_window}->set_border_width(0);
  $kernel->signal_ui_destroy( $heap->{main_window} );
  $heap->{notebook} = Gtk2::Notebook->new;
  $heap->{notebook}->set_show_tabs(TRUE);
  $heap->{notebook}->set_tab_pos('bottom');
  $heap->{main_window}->add($heap->{notebook});
  $heap->{main_window}->show_all;

  my $irc = $heap->{irc};
  $irc->yield( register => 'all' );
  $irc->yield( connect => { } );
}
