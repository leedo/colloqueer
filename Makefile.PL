use inc::Module::Install;

name     'App-Colloqueer';

abstract 'WebKitGTK+ IRC client';
author   'Lee Aylward <lee@laylward.com>';
version  '0.01';
license  'perl';

requires 'File::ShareDir'      => 0;
requires 'File::HomeDir'       => 0;
requires 'Moose'               => 0;
requires 'Gtk2'                => 0;
requires 'Gtk2::WebKit'        => 0;
requires 'Gtk2::Spell'         => 0;
requires 'POE'                 => 0;
requires 'POE::Loop::Glib'     => 0;
requires 'POE::Component::IRC' => 0;
requires 'DateTime'            => 0;
requires 'Template'            => 0;
requires 'XML::LibXML'         => 0;
requires 'XML::LibXSLT'        => 0;
requires 'Encode'              => 0;
requires 'YAML::Any'           => 0;
requires 'HTML::Entities'      => 0,

install_script 'colloqueer';
install_share  'share';

WriteAll;
