use inc::Module::Install;

name  'App-Colloqueer';

abstract 'WebKitGTK+ IRC client';
author 'Lee Aylward <lee@laylward.com>';
version '0.01';
license 'perl';

requires  'File::ShareDir';
requires  'File::HomeDir';
requires  'Moose';
requires  'Gtk2';
requires  'Gtk2::WebKit';
requires  'Gtk2::Spell';
requires  'POE';
requires  'POE::Loop::Glib';
requires  'POE::Component::IRC';
requires  'DateTime';
requires  'Template';
requires  'XML::LibXML';
requires  'XML::LibXSLT';
requires  'FindBin';
requires  'Encode';
requires  'YAML::Any';
requires  'IPC::Open2';

install_script 'colloqueer';
install_script 'irc2html.rb';
install_share  'share';
requires_external_bin 'ruby';

WriteAll;
