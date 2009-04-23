#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Gtk2 qw/-init/;
use POE qw/Component::IRC::State/;
use POE::Kernel { loop => 'Glib' };
use Colloqueer;

$0 = 'colloqueer';

my $app = Colloqueer->new(config => 'config.yaml');

POE::Session->create(
  package_states => [
    main => [ qw/_start irc_001 irc_public irc_msg irc_join irc_part irc_quit/ ],
  ],
  heap => { app => $app },
);

$poe_kernel->run();
exit 0;

sub irc_001 {
  my ($heap, $sender) = @_[HEAP, SENDER];
  for (@{$heap->{app}->channels}) {
    $heap->{app}->irc->yield( join => $_->name);
  }
}

sub irc_public {
  my ($heap, $who, $where, $what) = @_[HEAP, ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $heap->{app}->channel_by_name($where->[0]); 
  if (! $channel) {
    $channel = $heap->{app}->add_channel($where->[0]);
  }
  my $msg = Colloqueer::Message->new(
    nick    => $nick,
    hostmask => $who,
    text    => $what,
    channel => $channel,
  );
  $channel->add_message($msg);
}

sub irc_msg {
  my ($heap, $who, $where, $what) = @_[HEAP, ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $heap->{app}->channel_by_name($nick); 
  if (! $channel) {
    $channel = $heap->{app}->add_channel($nick);
  }
  my $msg = Colloqueer::Message->new(
    nick    => $nick,
    hostmask => $who,
    text    => $what,
    channel => $channel,
  );
  $channel->add_message($msg);
}


sub irc_join {
  my ($heap, $who, $to) = @_[HEAP, ARG0, ARG1];
  my $nick = ( split /!/, $who )[0];
  return if $nick eq $heap->{app}->nick;
  return unless my $channel = $heap->{app}->channel_by_name($to); 
  my $event = Colloqueer::Event->new(
    nick  => $nick,
    hostmask => $who,
    message => "joined the chat room.",
    channel => $channel,
  );
  $channel->add_event($event);
}

sub irc_part {
  my ($heap, $who, $to, $message) = @_[HEAP, ARG0, ARG1, ARG2];
  my $nick = ( split /!/, $who )[0];
  $message = "left" unless $message;
  print STDERR "$to $nick $message\n";
  return if $nick eq $heap->{app}->nick;
  return unless my $channel = $heap->{app}->channel_by_name($to); 
  my $event = Colloqueer::Event->new(
    nick  => $nick,
    hostmask => $who,
    message => "left the chat room. ($message)",
    channel => $channel,
  );
  $channel->add_event($event);
}

sub irc_quit {
  my ($heap, $who, $message) = @_[HEAP, ARG0, ARG1];
  my $nick = ( split /!/, $who )[0];
  $message = "quit" unless $message;
  print STDERR "$nick $message\n";
  return if $nick eq $heap->{app}->nick;
  return unless my $channel = $heap->{app}->channel_by_name($to); 
  my $event = Colloqueer::Event->new(
    nick  => $nick,
    hostmask => $who,
    message => "quit. ($message)",
    channel => $channel,
  );
  $channel->add_event($event);
}

sub _start {
  my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
  $kernel->signal_ui_destroy( $heap->{app}->window );
  $heap->{app}->irc->yield( register => 'all' );
  $heap->{app}->irc->yield( connect => { } );
}
