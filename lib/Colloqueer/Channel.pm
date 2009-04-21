package Colloqueer::Channel;
use Moose;
use Colloqueer;
use Colloqueer::Message;
use Gtk2::Gdk::Keysyms;
use Gtk2::WebKit;
use Glib qw/TRUE FALSE/;

has 'app' => (
  isa => 'Colloqueer',
  is => 'ro'
);

has 'name' => (
  isa => 'Str',
  is => 'ro',
  required => 1
);

has 'msgs' => (
  isa => 'ArrayRef[Colloqueer::Message]',
  is => 'rw',
  default => sub { [] }
);

has 'members' => (
  isa => 'ArrayRef[Str]',
  is => 'rw'
);

has 'webview' => (
  isa => 'Gtk2::WebKit::WebView',
  is => 'rw'
);

has 'entry' => (
  isa => 'Gtk2::Entry',
  is => 'rw'
);

has 'lastnick' => (
  isa => 'Str',
  is => 'rw',
  default => '',
);

has 'active' => (
  isa => 'Bool',
  is => 'rw',
  default => 1,
);

sub BUILD {
  my $self = shift;

  my $paned = Gtk2::VPaned->new;
  my $frame = Gtk2::Frame->new;
  $self->webview(Gtk2::WebKit::WebView->new);
  $self->webview->load_html_string($self->app->blank_html, '');
  $self->entry(Gtk2::Entry->new);

  $self->entry->signal_connect("key_press_event", sub {$self->handle_input(@_)});
  $frame->add($self->webview);
  $paned->pack1($frame, TRUE, FALSE);
  $paned->pack2($self->entry, FALSE, FALSE);
  $self->app->notebook->append_page($paned, $self->_build_label);
  $self->app->window->show_all;
}

sub handle_input {
  my ($self, $widget, $event) = @_;
  if ($event->keyval == $Gtk2::Gdk::Keysyms{Return}) {
    if ($widget->get_text =~ /^\/(.+)/) {
      $self->app->handle_command($1);
    }
    else {
      $self->app->irc->yield(privmsg => $self->name => $widget->get_text);
      push @{$self->msgs}, Colloqueer::Message->new(
        app     => $self->app,
        channel => $self,
        nick    => $self->app->nick,
        text    => $widget->get_text,
      );
    }
    $widget->set_text('');
  }
}

sub add_message {
  my ($self, $msg) = @_;
  push @{$self->msgs}, $msg;
}

sub _build_label {
  my $self = shift;
  my $notebook = $self->app->notebook;
  my $hbox = Gtk2::HBox->new;
  my $label = Gtk2::Label->new($self->name);
  my $eventbox = Gtk2::EventBox->new();
  $eventbox->set_size_request('16', '16');
  my $image = Gtk2::Image->new_from_file(
    $self->app->share_dir . '/images/roomTab.png');
  $eventbox->add($image);
  $hbox->pack_start ($label, TRUE, TRUE, 0);
  $hbox->pack_start ($eventbox, FALSE, FALSE, 0);
  $eventbox->signal_connect('button-release-event' => sub {
    $self->active(0);
    $self->app->remove_channel($self);
  });
  $eventbox->signal_connect('enter-notify-event' => sub {
    $image->set_from_file(
      $self->app->share_dir . '/images/aquaTabClose.png');
  });
  $eventbox->signal_connect('leave-notify-event' => sub {
    $image->set_from_file(
      $self->app->share_dir . '/images/roomTab.png');
  });
  $label->show;
  $image->show;
  $eventbox->show;
  return $hbox;
}

sub display_messages {
  my $self = shift;
  return unless $self->active;
  my $title = $self->webview->get_main_frame->get_title || '__empty__';
  return unless @{ $self->msgs } and $title eq '__empty__';

  my ($consecutive, $lastnick, @msg_out, @buff);
  $consecutive = 1 if $self->msgs->[0]->nick eq $self->lastnick;

  for my $msg (shift @{ $self->msgs }) {
    if (@buff > 0 and $msg->nick ne $lastnick) {
      last if $consecutive;
      push @msg_out, $self->app->format_messages(@buff);
      @buff = ();
    }
    push @buff, $msg;
    $lastnick = $msg->nick;
  }
  push @msg_out, $self->app->format_messages($consecutive, @buff);
  $self->lastnick($lastnick);
  my $html = join '', @msg_out;
  if (@msg_out > 0) {
    print STDERR "$html\n\n";
  }
  $self->webview->execute_script("document.title='$html';");
}

1;
