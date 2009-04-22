package Colloqueer::Channel;
use Moose;
use Colloqueer;
use Colloqueer::Message;
use Colloqueer::Event;
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

has 'events' => (
  isa => 'ArrayRef[Colloqueer::Event]',
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

has 'pane' => (
  isa => 'Gtk2::VPaned',
  is => 'rw',
  default => sub {
    return Gtk2::VPaned->new;
  }
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

has 'cleared' => (
  isa => 'Bool',
  is => 'rw',
  default => 0,
);

has 'icon' => (
  isa => 'Gtk2::Image',
  is => 'ro',
  default => sub {return Gtk2::Image->new}
);

has 'tabnum' => (
  isa => 'Int',
  is => 'rw'
);

sub BUILD {
  my $self = shift;

  my $frame = Gtk2::Frame->new;
  $self->webview(Gtk2::WebKit::WebView->new);
  $self->webview->load_html_string($self->app->blank_html, '');
  $self->entry(Gtk2::Entry->new);

  $self->entry->signal_connect("key_press_event", sub {$self->handle_input(@_)});
  $frame->add($self->webview);
  $self->pane->pack1($frame, TRUE, FALSE);
  $self->pane->pack2($self->entry, FALSE, FALSE);
  $self->tabnum($self->app->notebook->append_page($self->pane, $self->_build_label));
  $self->app->window->show_all;
}

sub handle_input {
  my ($self, $widget, $event) = @_;
  if ($event->keyval == $Gtk2::Gdk::Keysyms{Return}) {
    if ($widget->get_text =~ /^\/clear/) {
      $self->webview->load_html_string($self->app->blank_html, '');
      $self->cleared(1);
    }
    elsif ($widget->get_text =~ /^\/(.+)/) {
      $self->app->handle_command($1);
    }
    else {
      $self->app->irc->yield(privmsg => $self->name => $widget->get_text);
      push @{$self->msgs}, Colloqueer::Message->new(
        app     => $self->app,
        channel => $self,
        nick    => $self->app->nick,
        hostmask => $self->app->nick."!localhost",
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

sub add_event {
  my ($self, $msg) = @_;
  push @{$self->events}, $msg;
}

sub clear_events {
  my ($self, $msg) = @_;
  $self->events([]);
}

sub _build_label {
  my ($self, $messages) = @_;
  my $notebook = $self->app->notebook;
  my $hbox = Gtk2::HBox->new;
  my $label = Gtk2::Label->new($self->name);
  my $eventbox = Gtk2::EventBox->new();
  $eventbox->set_size_request('16', '16');
  $self->icon->set_from_file(
    $self->app->share_dir . "/images/roomTab.png");
  $eventbox->add($self->icon);
  $hbox->pack_start ($eventbox, FALSE, FALSE, 0);
  $hbox->pack_start ($label, TRUE, TRUE, 0);
  $eventbox->signal_connect('button-release-event' => sub {
    $self->active(0);
    $self->app->remove_channel($self);
  });
  $eventbox->signal_connect('enter-notify-event' => sub {
    $self->icon->set_from_file(
      $self->app->share_dir . '/images/aquaTabClose.png');
  });
  $eventbox->signal_connect('leave-notify-event' => sub {
    $self->icon->set_from_file(
      $self->app->share_dir . '/images/roomTab.png');
  });
  $label->show;
  $self->icon->show;
  $eventbox->show;
  return $hbox;
}

sub focused {
  my $self = shift;
  return $self->tabnum == $self->app->notebook->get_current_page;
}

sub display_message {
  my $self = shift;
  return unless $self->active;
  return unless @{ $self->msgs } or @{ $self->events };

  my $title = $self->webview->get_main_frame->get_title;
  return unless $title and $title eq '__empty__';
  
  my $html = '';

  if (my $msg = shift @{ $self->msgs }) {
    my $consecutive = 1 if $msg->nick eq $self->lastnick and ! $self->cleared;
    $self->lastnick($msg->nick);
    $html = $self->app->format_messages($consecutive, $msg);
    $self->cleared(0);
    if (! $self->focused) {
      $self->icon->set_from_file(
        $self->app->share_dir . "/images/roomTabNewMessage.png");
    }
  }
  elsif (@{$self->events}) {
    my @out;
    push @out, $self->app->format_event($_) for @{ $self->events };
    $self->cleared(1);
    $self->clear_events;
    $html = join '', @out;
  }

  $self->webview->execute_script("document.title='$html';");
}

1;
