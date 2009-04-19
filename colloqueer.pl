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
use JSON::Any;

open my $config_fh, '<', 'config.yaml';

my $config = Load(join "\n", <$config_fh>);

my $url_re = q{\b(s?https?|ftp|file|gopher|s?news|telnet|mailbox):} .
             q{(//[-A-Z0-9_.]+:\d*)?} .
             q{[-A-Z0-9_=?\#:\$\@~\`%&*+|\/.,;\240]+};

my $irc = POE::Component::IRC->spawn( 
  nick      => $config->{nick},
  port      => $config->{server}{port},
  ircname   => $config->{ircname},
  username  => $config->{server}{username},
  password  => $config->{server}{password},
  server    => $config->{server}{host},
) or die $!;

POE::Session->create(
  package_states => [
    main => [ qw/_start irc_001 irc_public irc_join irc_part irc_invite/ ],
  ],
  heap => {
    parser    => XML::LibXML->new(),
    xslt      => XML::LibXSLT->new(),
    irc       => $irc,
    style     => $config->{theme},
    nick      => $config->{nick},
    channels  => { map {$_ => {}} @{$config->{channels}} },
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
  $entry->signal_connect("key_press_event", sub {
    my ($widget, $event) = @_;
    if ($event->keyval == $Gtk2::Gdk::Keysyms{Return}) {
      if ($widget->get_text =~ /^\/(.+)/) {
        handle_command($heap, $1);
      }
      else {
        $irc->yield(privmsg => $channel => $widget->get_text);
        my $msg = {
          nick  => $heap->{nick},
          hostmask => $heap->{nick},
          text  => irc2html($widget->get_text),
          date  => DateTime->now,
          id    => encode_base64($heap->{nick}.time)
        };
        update_channel($channel, $msg, $heap);
      }
      $widget->set_text('');
    }
  });
  $frame->add($wv);
  $paned->pack1($frame, TRUE, FALSE);
  $paned->pack2($entry, FALSE, FALSE);
  $heap->{channels}{$channel}{page} = scalar(keys %{ $heap->{channels} }) - 1;
  $heap->{channels}{$channel}{lastnick} = '';
  $heap->{notebook}->append_page($paned, make_label($channel, $heap));
  $heap->{channels}{$channel}{view} = $wv;
  $heap->{main_window}->show_all;
  $heap->{notebook}->set_current_page($heap->{notebook}->page_num($paned));

  $heap->{tt}->process('base.html', undef, \(my $html)); 
  $heap->{channels}{$channel}{view}->load_html_string($html, '/');
}

sub make_label {
  my ($channel,$heap) = @_;
  my $notebook = $heap->{notebook};
  my $hbox = Gtk2::HBox->new;
  my $label = Gtk2::Label->new($channel);
  my $button = Gtk2::Button->new();
  my $image = Gtk2::Image->new_from_stock('gtk-close', 'menu');
  $button->set_image($image);
  $button->set_relief('none');
  $hbox->pack_start ($label, TRUE, TRUE, 0);
  $hbox->pack_start ($button, FALSE, FALSE, 0);
  $button->signal_connect(clicked => sub {
    $heap->{irc}->yield( part => $channel );
    $notebook->remove_page ($notebook->get_current_page);
  });
  $label->show;
  $button->show;
  $hbox
} 

sub irc_invite {
  my ($heap, $channel) = @_[HEAP, ARG0];
  $heap->{irc}->yield( join => $channel);
  setup_tab($heap, $channel);
}

sub irc_join {
  my ($heap, $channel) = @_[HEAP, ARG0];
}

sub irc_part {
  my ($heap, $channel, $message) = @_[HEAP, ARG1];
}

sub handle_command {
  my ($heap, $command) = @_;
  if ($command =~ /^join (.+)/) {
    $heap->{irc}->yield( join => $1);
    setup_tab($heap, $1);
  }
  elsif ($command =~ /^part (.+)/) {
    $heap->{irc}->yield( part => $1);
    $heap->{notebook}->remove_page($heap->{channels}{$1}{page});
  }
}

sub irc_public {
  my ($heap, $sender, $who, $where, $what) = @_[HEAP, SENDER, ARG0 .. ARG2];
  my $from = ( split /!/, $who )[0];
  my $channel = $where->[0];
  return unless exists $heap->{channels}{$channel};

  my $msg = {
    nick  => $from,
    hostmask => $who,
    text  => irc2html($what),
    date  => DateTime->now,
    id    => encode_base64($from.time)
  };
  update_channel($channel, $msg, $heap);
}

sub update_channel {
  my ($channel, $msg, $heap) = @_;
  $msg->{id} =~ s/=*\n//; # strip trailing mime crud
  my $consecutive = $heap->{channels}{$channel}{lastnick} eq $msg->{nick};
  my $html = format_message($heap, $msg, $consecutive);
  $html =~ s/'/\\'/g;
  $html =~ s/\n//g;
  $heap->{channels}{$channel}{lastnick} = $msg->{nick};
  $heap->{channels}{$channel}{view}->execute_script("document.title='$html';");
}

sub format_message {
  my ($heap, $msg, $consecutive) = @_;
  $heap->{tt}->process('message.xml', {
    msg   => $msg,
    consecutive => $consecutive,
    self  => $msg->{nick} eq $heap->{nick} ? 1 : 0,
  }, \(my $message)) or die $!;
  my $doc = $heap->{parser}->parse_string($message,{encoding => 'utf8'});
  my $results = $heap->{style_doc}->transform($doc,
    XML::LibXSLT::xpath_to_string(
      consecutiveMessage => $consecutive ? 'yes' : 'no',
      fromEnvelope => $consecutive ? 'no' : 'yes',
      bulkTransform => $consecutive ? 'no' : 'yes',
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

  $heap->{main_window} = Gtk2::Window->new('toplevel');
  $heap->{main_window}->set_default_size(650,500);
  $heap->{main_window}->set_border_width(0);
  $kernel->signal_ui_destroy( $heap->{main_window} );
  $heap->{notebook} = Gtk2::Notebook->new;
  $heap->{notebook}->set_show_tabs(TRUE);
  $heap->{notebook}->set_tab_pos('bottom');
  $heap->{main_window}->add($heap->{notebook});
  $heap->{main_window}->show_all;

  $heap->{irc}->yield( register => 'all' );
  $heap->{irc}->yield( connect => { } );
}
