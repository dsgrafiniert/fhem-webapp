##############################################
# $Id: 01_FHEMWEBAPP.pm 4761 2014-01-28 09:13:13Z rudolfkoenig $
package main;

use strict;
use warnings;
use TcpServerUtils;
use HttpUtils;
use Text::Xslate qw(mark_raw);

#########################
# Forward declaration
sub FWA_IconURL($);
sub FWA_iconName($);
sub FWA_iconPath($);
sub FWA_answerCall($);
sub FWA_dev2image($;$);
sub FWA_devState($$@);
sub FWA_digestCgi($);
sub FWA_doDetail($);
sub FWA_fatal($);
sub FWA_fileList($);
sub FWA_parseColumns();
sub FWA_htmlEscape($);
sub FWA_logWrapper($);
sub FWA_makeEdit($$$);
sub FWA_makeImage(@);
sub FWA_makeTable($$$@);
sub FWA_makeTableFromArray($$@);
sub FWA_pF($@);
sub FWA_pH(@);
sub FWA_pHPlain(@);
sub FWA_pO(@);
sub FWA_readIcons($);
sub FWA_readIconsFrom($$);
sub FWA_returnFileAsStream($$$$$);
sub FWA_roomStatesForInform($);
sub FWA_menuList($);
sub FWA_select($$$$$@);
sub FWA_serveSpecial($$$$);
sub FWA_roomDetail();
sub FWA_style($$);
sub FWA_submit($$@);
sub FWA_textfield($$$);
sub FWA_textfieldv($$$$);
sub FWA_updateHashes();
sub FWA_render($$);

use vars qw($FWA_dir);     # base directory for web server
use vars qw($FWA_icondir); # icon base directory
use vars qw($FWA_appdir);  # css directory
use vars qw($FWA_gplotdir);# gplot directory
use vars qw($MWA_dir);     # moddir (./FHEM), needed by edit Files in new
                          # structure

use vars qw($FWA_ME);      # webname (default is fhem), used by 97_GROUP/weblink
use vars qw($FWA_ss);      # is smallscreen, needed by 97_GROUP/95_VIEW
use vars qw($FWA_tp);      # is touchpad (iPad / etc)
use vars qw($FWA_sp);      # stylesheetPrefix

# global variables, also used by 97_GROUP/95_VIEW/95_FLOORPLAN
use vars qw(%FWA_types);   # device types,
use vars qw($FWA_RET);     # Returned data (html)
use vars qw($FWA_RETTYPE); # image/png or the like
use vars qw($FWA_wname);   # Web instance
use vars qw($FWA_subdir);  # Sub-path in URL, used by FLOORPLAN/weblink
use vars qw(%FWA_pos);     # scroll position
use vars qw($FWA_cname);   # Current connection name
use vars qw(%FWA_hiddenroom); # hash of hidden rooms, used by weblink
use vars qw($FWA_plotmode);# Global plot mode (WEB attribute), used by SVG
use vars qw($FWA_plotsize);# Global plot size (WEB attribute), used by SVG
use vars qw(%FWA_webArgs); # all arguments specified in the GET
use vars qw(@FWA_fhemwebjs);# List of fhemweb*js scripts to load
use vars qw($FWA_detail);   # currently selected device for detail view
use vars qw($FWA_cmdret);   # Returned data by the fhem call
use vars qw($FWA_room);      # currently selected room
use vars qw($FWA_formmethod);

$FWA_formmethod = "post";

my $FWA_zlib_checked;
my $FWA_use_zlib = 1;
my $FWA_activateInform = 0;

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
# Note: for delivering SVG plots we fork
my @FWA_httpheader; # HTTP header, line by line
my @FWA_enc;        # Accepted encodings (browser header)
my $FWA_data;       # Filecontent from browser when editing a file
my %FWA_icons;      # List of icons
my @FWA_iconDirs;   # Directory search order for icons
my $FWA_RETTYPE;    # image/png or the like
my %FWA_rooms;      # hash of all rooms
my %FWA_types;      # device types, for sorting
my %FWA_hiddengroup;# hash of hidden groups
my $FWA_inform;
my $FWA_XHR;        # Data only answer, no HTML
my $FWA_jsonp;      # jasonp answer (sending function calls to the client)
my $FWA_headercors; #
my $FWA_chash;      # client fhem hash
my $FWA_encoding="UTF-8";
my $FWA_xslate;


#####################################
sub
FHEMWEBAPP_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "FWA_Read";
  $hash->{GetFn}   = "FWA_Get";
  $hash->{SetFn}   = "FWA_Set";
  $hash->{AttrFn}  = "FWA_Attr";
  $hash->{DefFn}   = "FWA_Define";
  $hash->{UndefFn} = "FWA_Undef";
  $hash->{NotifyFn}= "FWA_SecurityCheck";
  $hash->{ActivateInformFn} = "FWA_ActivateInform";
  no warnings 'qw';
  my @attrList = qw(
    CORS:0,1
    HTTPS:1,0
    SVGcache:1,0
    allowfrom
    basicAuth
    basicAuthMsg
    column
    endPlotNow:1,0
    endPlotToday:1,0
    fwcompress:0,1
    hiddengroup
    hiddenroom
    iconPath
    longpoll:0,1
    longpollSVG:1,0
    menuEntries
    plotfork:1,0
    plotmode:gnuplot,gnuplot-scroll,SVG
    plotsize
    nrAxis
    redirectCmds:0,1
    refresh
    reverseLogs:0,1
    roomIcons
    sortRooms
    smallscreen:unused
    stylesheetPrefix
    touchpad:unused
    webname
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);


  ###############
  # Initialize internal structures
  map { addToAttrList($_) } ( "webCmd", "icon", "devStateIcon",
                                "sortby", "devStateStyle");
  InternalTimer(time()+60, "FWA_closeOldClients", 0, 0);
  
  $FWA_dir      = "$attr{global}{modpath}/www";
  $FWA_icondir  = "$FWA_dir/images";
  $FWA_appdir   = "$FWA_dir/app";
  $FWA_gplotdir = "$FWA_dir/gplot";
  if(opendir(DH, "$FWA_appdir/js")) {
    @FWA_fhemwebjs = sort grep /^fhemweb.*js$/, readdir(DH);
    closedir(DH);
  }

  $FWA_xslate=Text::Xslate->new( path => ["$FWA_appdir/tpl"] );

  $data{webCmdFn}{slider}     = "FWA_sliderFn";
  $data{webCmdFn}{timepicker} = "FWA_timepickerFn";
  $data{webCmdFn}{noArg}      = "FWA_noArgFn";
  $data{webCmdFn}{textField}  = "FWA_textFieldFn";
  $data{webCmdFn}{"~dropdown"}= "FWA_dropdownFn"; # Should be the last
}

sub 
FWA_render($$)
{
  my($tpl, $data) = @_;
  my $ret = "";
  eval{
    $ret = $FWA_xslate->render($tpl, $data) 
  };
  if($@)
  {
    my $msg = $@;
    eval{
      $ret = $FWA_xslate->render("error.tx", {error => "Error rendering template: $msg"});
    };
    return $@ if $@;
  }
  return $ret;
}

#####################################
sub
FWA_SecurityCheck($$)
{
  my ($ntfy, $dev) = @_;
  return if($dev->{NAME} ne "global" ||
            !grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}));
  my $motd = AttrVal("global", "motd", "");
  if($motd =~ "^SecurityCheck") {
    my @list = grep { !AttrVal($_, "basicAuth", undef) }
               devspec2array("TYPE=FHEMWEBAPP");
    $motd .= (join(",", sort @list)." has no basicAuth attribute.\n")
        if(@list);
    $attr{global}{motd} = $motd;
  }
  $modules{FHEMWEBAPP}{NotifyFn}= "FWA_Notify";
  return;
}

#####################################
sub
FWA_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMWEBAPP [IPV6:]<tcp-portnr> [global]"
        if($port !~ m/^(IPV6:)?\d+$/ || ($global && $global ne "global"));

  foreach my $pe ("fhemSVG", "openautomation", "default") {
    FWA_readIcons($pe);
  }

  my $ret = TcpServer_Open($hash, $port, $global);

  # Make sure that fhem only runs once
  if($ret && !$init_done) {
    Log3 $hash, 1, "$ret. Exiting.";
    exit(1);
  }

  return $ret;
}

#####################################
sub
FWA_Undef($$)
{
  my ($hash, $arg) = @_;
  return TcpServer_Close($hash);
}

#####################################
sub
FWA_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    TcpServer_Accept($hash, "FHEMWEBAPP");
    return;
  }

  $FWA_chash = $hash;
  $FWA_wname = $hash->{SNAME};
  $FWA_cname = $name;
  $FWA_subdir = "";

  my $c = $hash->{CD};
  if(!$FWA_zlib_checked) {
    $FWA_zlib_checked = 1;
    $FWA_use_zlib = AttrVal($FWA_wname, "fwcompress", 1);
    if($FWA_use_zlib) {
      eval { require Compress::Zlib; };
      if($@) {
        $FWA_use_zlib = 0;
        Log3 $FWA_wname, 1, $@;
        Log3 $FWA_wname, 1,
               "$FWA_wname: Can't load Compress::Zlib, deactivating compression";
        $attr{$FWA_wname}{fwcompress} = 0;
      }
    }
  }



  # Data from HTTP Client
  my $buf;
  my $ret = sysread($c, $buf, 1024);

  if(!defined($ret) || $ret <= 0) {
    CommandDelete(undef, $name);
    Log3 $FWA_wname, 4, "Connection closed for $name";
    return;
  }

  $hash->{BUF} .= $buf;
  if($defs{$FWA_wname}{SSL}) {
    while($c->pending()) {
      sysread($c, $buf, 1024);
      $hash->{BUF} .= $buf;
    }
  }

  if(!$hash->{HDR}) {
    return if($hash->{BUF} !~ m/^(.*)(\n\n|\r\n\r\n)(.*)$/s);
    $hash->{HDR} = $1;
    $hash->{BUF} = $3;
    if($hash->{HDR} =~ m/Content-Length: ([^\r\n]*)/s) {
      $hash->{CONTENT_LENGTH} = $1;
    }
  }
  return if($hash->{CONTENT_LENGTH} &&
            length($hash->{BUF})<$hash->{CONTENT_LENGTH});

  @FWA_httpheader = split("[\r\n]", $hash->{HDR});
  delete($hash->{HDR});

  my @origin = grep /Origin/, @FWA_httpheader;
  $FWA_headercors = (AttrVal($FWA_wname, "CORS", 0) ?
              "Access-Control-Allow-".$origin[0]."\r\n".
              "Access-Control-Allow-Methods: GET OPTIONS\r\n".
              "Access-Control-Allow-Headers: Origin, Authorization, Accept\r\n".
              "Access-Control-Allow-Credentials: true\r\n".
              "Access-Control-Max-Age:86400\r\n" : "");


  #############################
  # BASIC HTTP AUTH
  my $basicAuth = AttrVal($FWA_wname, "basicAuth", undef);
  my @headerOptions = grep /OPTIONS/, @FWA_httpheader;
  if($basicAuth) {
    my @authLine = grep /Authorization: Basic/, @FWA_httpheader;
    my $secret = $authLine[0];
    $secret =~ s/^Authorization: Basic // if($secret);
    my $pwok = ($secret && $secret eq $basicAuth);
    if($secret && $basicAuth =~ m/^{.*}$/ || $headerOptions[0]) {
      eval "use MIME::Base64";
      if($@) {
        Log3 $FWA_wname, 1, $@;

      } else {
        my ($user, $password) = split(":", decode_base64($secret));
        $pwok = eval $basicAuth;
        Log3 $FWA_wname, 1, "basicAuth expression: $@" if($@);
      }
    }
    if($headerOptions[0]) {
      print $c "HTTP/1.1 200 OK\r\n",
             $FWA_headercors,
             "Content-Length: 0\r\n\r\n";
      delete $hash->{CONTENT_LENGTH};
      delete $hash->{BUF};
      return;
      exit(1);
    };
    if(!$pwok) {
      my $msg = AttrVal($FWA_wname, "basicAuthMsg", "Fhem: login required");
      print $c "HTTP/1.1 401 Authorization Required\r\n",
             "WWW-Authenticate: Basic realm=\"$msg\"\r\n",
             $FWA_headercors,
             "Content-Length: 0\r\n\r\n";
      delete $hash->{CONTENT_LENGTH};
      delete $hash->{BUF};
      return;
    };
  }
  #############################

  my $now = time();
  @FWA_enc = grep /Accept-Encoding/, @FWA_httpheader;
  my ($method, $arg, $httpvers) = split(" ", $FWA_httpheader[0], 3);
  $arg .= "&".$hash->{BUF} if($hash->{CONTENT_LENGTH});
  delete $hash->{CONTENT_LENGTH};
  delete $hash->{BUF};
  $hash->{LASTACCESS} = $now;

  $arg = "" if(!defined($arg));
  Log3 $FWA_wname, 4, "HTTP $name GET $arg";
  my $pid;
  if(AttrVal($FWA_wname, "plotfork", undef)) {
    # Process SVG rendering as a parallel process
    return if(($arg =~ m+/SVG_showLog+) && ($pid = fork));
  }

  my $cacheable = FWA_answerCall($arg);
  return if($cacheable == -1); # Longpoll / inform request;

  my $compressed = "";
  # if(($FWA_RETTYPE =~ m/text/i ||
      # $FWA_RETTYPE =~ m/svg/i ||
      # $FWA_RETTYPE =~ m/script/i) &&
     # (int(@FWA_enc) == 1 && $FWA_enc[0] =~ m/gzip/) &&
     # $FWA_use_zlib) {
    # $FWA_RET = Compress::Zlib::memGzip($FWA_RET);
    # $compressed = "Content-Encoding: gzip\r\n";
  # }

  my $length = length($FWA_RET);
  my $expires = ($cacheable?
                        ("Expires: ".localtime($now+900)." GMT\r\n") : "");
  Log3 $FWA_wname, 4, "$arg / RL:$length / $FWA_RETTYPE / $compressed / $expires";
  print $c "HTTP/1.1 200 OK\r\n",
           "Content-Length: $length\r\n",
           $expires, $compressed, $FWA_headercors,
           "Content-Type: $FWA_RETTYPE\r\n\r\n",
           $FWA_RET;
  exit if(defined($pid));
}

###########################
sub
FWA_serveSpecial($$$$)
{
  my ($file,$ext,$dir,$cacheable)= @_;
  $file =~ s,\.\./,,g; # little bit of security

  $file = "$FWA_sp$file" if($ext eq "css" && -f "$dir/$FWA_sp$file.$ext");
  $FWA_RETTYPE = ext2MIMEType($ext);
  return FWA_returnFileAsStream("$dir/$file.$ext", "",
                                        $FWA_RETTYPE, 0, $cacheable);
}

sub
FWA_answerCall($)
{
  my ($arg) = @_;
  my $me=$defs{$FWA_cname};      # cache, else rereadcfg will delete us

  $FWA_RET = "";
  $FWA_RETTYPE = "text/html; charset=$FWA_encoding";
  $FWA_ME = "/" . AttrVal($FWA_wname, "webname", "fhem");

  $MWA_dir = "$attr{global}{modpath}/FHEM";
  $FWA_sp = AttrVal($FWA_wname, "stylesheetPrefix", "");
  $FWA_ss = ($FWA_sp =~ m/smallscreen/);
  $FWA_tp = ($FWA_sp =~ m/smallscreen|touchpad/);
  @FWA_iconDirs = grep { $_ } split(":", AttrVal($FWA_wname, "iconPath",
                                "$FWA_sp:default:fhemSVG:openautomation"));
  if($arg =~ m,$FWA_ME/floorplan/([a-z0-9.:_]+),i) { # FLOORPLAN: special icondir
    unshift @FWA_iconDirs, $1;
    FWA_readIcons($1);
  }

  # /icons/... => current state of ...
  # also used for static images: unintended, but too late to change
  if($arg =~ m,^$FWA_ME/icons/(.*)$,) {
    my ($icon,$cacheable) = (urlDecode($1), 1);
    my $iconPath = FWA_iconPath($icon);

    # if we do not have the icon, we convert the device state to the icon name
    if(!$iconPath) {
      ($icon, undef, undef) = FWA_dev2image($icon);
      $cacheable = 0;
      return 0 if(!$icon);
      $iconPath = FWA_iconPath($icon);
    }
    $iconPath =~ m/(.*)\.([^.]*)/;
    return FWA_serveSpecial($1, $2, $FWA_icondir, $cacheable);

  } elsif($arg =~ m,^$FWA_ME/(.*)/([^/]*)$,) {          # the "normal" case
    my ($dir, $ofile, $ext) = ($1, $2, "");
    $dir =~ s/\.\.//g;
    $dir =~ s,www/,,g; # Want commandref.html to work from file://...

    my $file = $ofile;
    $file =~ s/\?.*//; # Remove timestamp of CSS reloader
    if($file =~ m/^(.*)\.([^.]*)$/) {
      $file = $1; $ext = $2;
    }
    my $ldir = "$FWA_dir/$dir";
    $ldir = "$FWA_appdir" if($dir eq "css" || $dir eq "js"); # FLOORPLAN compat
    $ldir = "$attr{global}{modpath}/docs" if($dir eq "docs");

    if(-r "$ldir/$file.$ext") {                # no return for FLOORPLAN
      return FWA_serveSpecial($file, $ext, $ldir, ($arg =~ m/nocache/) ? 0 : 1);
    }
    $arg = "/$dir/$ofile";

  } elsif($arg =~ m/^$FWA_ME(.*)/) {
    $arg = $1; # The stuff behind FWA_ME, continue to check for commands/FWEXT

  } else {
    my $c = $me->{CD};
    Log3 $FWA_wname, 4, "$FWA_wname: redirecting $arg to $FWA_ME";
    print $c "HTTP/1.1 302 Found\r\n",
             "Content-Length: 0\r\n", $FWA_headercors,
             "Location: $FWA_ME\r\n\r\n";
    return -1;

  }


  $FWA_plotmode = AttrVal($FWA_wname, "plotmode", "SVG");
  $FWA_plotsize = AttrVal($FWA_wname, "plotsize", $FWA_ss ? "480,160" :
                                                $FWA_tp ? "640,160" : "800,160");
  my ($cmd, $cmddev) = FWA_digestCgi($arg);


  if($FWA_inform) {      # Longpoll header
    if($FWA_inform =~ /type=/) {
      foreach my $kv (split(";", $FWA_inform)) {
        my ($key,$value) = split("=", $kv, 2);
        $me->{inform}{$key} = $value;
      }

    } else {                     # Compatibility mode
      $me->{inform}{type}   = ($FWA_room ? "status" : "raw");
      $me->{inform}{filter} = ($FWA_room ? $FWA_room : ".*");
    }
    my $filter = $me->{inform}{filter};
    $filter = "NAME=.*" if($filter eq "room=all");
    $filter = "room!=.*" if($filter eq "room=Unsorted");

    my %h = map { $_ => 1 } devspec2array($filter);
    $me->{inform}{devices} = \%h;

    # NTFY_ORDER is larger than the normal order (50-)
    $me->{NTFY_ORDER} = $FWA_cname;   # else notifyfn won't be called
    %ntfyHash = ();

    my $c = $me->{CD};
    print $c "HTTP/1.1 200 OK\r\n",
       $FWA_headercors,
       "Content-Type: application/octet-stream; charset=$FWA_encoding\r\n\r\n",
       FWA_roomStatesForInform($me);
    return -1;
  }

  my $docmd = 0;
  $docmd = 1 if($cmd &&
                $cmd !~ /^showlog/ &&
                $cmd !~ /^style / &&
                $cmd !~ /^edit/);

  #If we are in XHR or json mode, execute the command directly
  if($FWA_XHR || $FWA_jsonp) {
    $FWA_cmdret = $docmd ? FWA_fC($cmd, $cmddev) : "";
    $FWA_RETTYPE = "text/plain; charset=$FWA_encoding";
    if($FWA_jsonp) {
      $FWA_cmdret =~ s/'/\\'/g;
      # Escape newlines in JavaScript string
      $FWA_cmdret =~ s/\n/\\\n/g;
      FWA_pO "$FWA_jsonp('$FWA_cmdret');";
    } else {
      FWA_pO $FWA_cmdret;
    }
    return 0;
  }

  ##############################
  # FHEMWEBAPP extensions (FLOORPLOAN, SVG_WriteGplot, etc)
  my $FWA_contentFunc;
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($arg !~ m/^$k/);
      $FWA_contentFunc = $h->{CONTENTFUNC};
      next if($h !~ m/HASH/ || !$h->{FUNC});
      #Returns undef as FWA_RETTYPE if it already sent a HTTP header
      no strict "refs";
      ($FWA_RETTYPE, $FWA_RET) = &{$h->{FUNC}}($arg);
      use strict "refs";
      return defined($FWA_RETTYPE) ? 0 : -1;
    }
  }


  #Now execute the command
  $FWA_cmdret = "";
  if($docmd) {
    $FWA_cmdret = FWA_fC($cmd, $cmddev);
    if($cmd =~ m/^define +([^ ]+) /) { # "redirect" after define to details
      $FWA_detail = $1;
    }
  }

  # Redirect after a command, to clean the browser URL window
  if($docmd && !$FWA_cmdret && AttrVal($FWA_wname, "redirectCmds", 1)) {
    my $tgt = $FWA_ME;
       if($FWA_detail) { $tgt .= "?detail=$FWA_detail" }
    elsif($FWA_room)   { $tgt .= "?room=$FWA_room" }
    my $c = $me->{CD};
    print $c "HTTP/1.1 302 Found\r\n",
             "Content-Length: 0\r\n", $FWA_headercors,
             "Location: $tgt\r\n",
             "\r\n";
    return -1;
  }

  FWA_updateHashes();

  my $t = AttrVal("global", "title", "Home, Sweet Home");
  
  # meta refresh in rooms only
  my $rf = "";
  if ($FWA_room) {
    $rf = AttrVal($FWA_wname, "refresh", "");
  }

  my @scripts = ();
  ########################
  # FW Extensions
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $item = $data{FWEXT}{$k};
      next if(!$item->{SCRIPT});
      my $script = $item->{SCRIPT};
      $script = ($script =~ m,^/,) ? "$FWA_ME$script" : "$FWA_ME/pgm2/$script";
      push(@scripts, $script);
    }
  }

  push(@scripts, "$FWA_ME/pgm2/svg.js") if($FWA_plotmode eq "SVG");
  if($FWA_plotmode eq"jsSVG") {
    push(@scripts, "$FWA_ME/pgm2/jsSVG.js");
  }
  foreach my $js (@FWA_fhemwebjs) {
    push(@scripts, "$FWA_ME/pgm2/$js");
  } 

  my $onload = AttrVal($FWA_wname, "longpoll", 1) ?
                      "onload=\"FWA_delayedStart()\"" : "";

  if($FWA_activateInform) {
    $FWA_cmdret = $FWA_activateInform = "";
    $cmd = "style eventMonitor";
  }

  my $content = "";
  my $content_preformatted = 0;
  if($FWA_cmdret) {
    $FWA_detail = "";
    $FWA_room = "";
    $FWA_cmdret = FWA_htmlEscape($FWA_cmdret);
    $FWA_cmdret =~ s/>/&gt;/g;
    $content_preformatted = $FWA_cmdret =~ m/\n/;
    $content = $FWA_cmdret;
  }

  my $menus = FWA_menuList($cmd);
  Log 3, $menus;
  if($FWA_contentFunc) {
    no strict "refs";
    my $ret = &{$FWA_contentFunc}($arg);
    use strict "refs";
    $content = $ret;   
    #return $ret if($ret);
  }

     if($cmd =~ m/^style /)     { $content = FWA_style($cmd,undef);     }
  elsif($FWA_detail)            { $content = FWA_doDetail($FWA_detail); }
  elsif($FWA_room)              { $content = FWA_roomDetail();            }
  elsif(!$FWA_cmdret &&
        !$FWA_contentFunc &&
        AttrVal("global", "motd", "none") ne "none") {
    my $motd = AttrVal("global","motd",undef);
    $motd =~ s/\n/<br>/g;
    $content = $motd;
  }
  my $html = FWA_render("index.tx", {
      title => $t,
      favicon => FWA_IconURL("favicon"),
      refresh => $rf,
      stylesheet => "$FWA_ME/app/css/style.css",
      scripts => \@scripts,
      onload => mark_raw($onload),
      menus => $menus,
      current_room => $FWA_room,
      content => mark_raw($content),
      is_content_preformatted => $content_preformatted,
      is_smallscreen => $FWA_ss,
      is_tablet => $FWA_tp,
    });
  FWA_pO $html;
  return 0;
}


###########################
# Digest CGI parameters
sub
FWA_digestCgi($)
{
  my ($arg) = @_;
  my (%arg, %val, %dev);
  my ($cmd, $c) = ("","","");

  %FWA_pos = ();
  $FWA_room = "";
  $FWA_detail = "";
  $FWA_XHR = undef;
  $FWA_jsonp = undef;
  $FWA_inform = undef;

  %FWA_webArgs = ();
  #Remove (nongreedy) everything including the first '?'
  $arg =~ s,^.*?[?],,;
  foreach my $pv (split("&", $arg)) {
    next if($pv eq ""); # happens when post forgot to set FWA_ME
    $pv =~ s/\+/ /g;
    $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
    my ($p,$v) = split("=",$pv, 2);

    # Multiline: escape the NL for fhem
    $v =~ s/[\r]//g if($v && $p && $p ne "data");
    $FWA_webArgs{$p} = $v;

    if($p eq "detail")       { $FWA_detail = $v; }
    if($p eq "room")         { $FWA_room = $v; }
    if($p eq "cmd")          { $cmd = $v; }
    if($p =~ m/^arg\.(.*)$/) { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/) { $val{$1} = $v; }
    if($p =~ m/^dev\.(.*)$/) { $dev{$1} = $v; }
    if($p =~ m/^cmd\.(.*)$/) { $cmd = $v; $c = $1; }
    if($p eq "pos")          { %FWA_pos =  split(/[=;]/, $v); }
    if($p eq "data")         { $FWA_data = $v; }
    if($p eq "XHR")          { $FWA_XHR = 1; }
    if($p eq "jsonp")        { $FWA_jsonp = $v; }
    if($p eq "inform")       { $FWA_inform = $v; }

  }
  $cmd.=" $dev{$c}" if(defined($dev{$c}));
  $cmd.=" $arg{$c}" if(defined($arg{$c}) &&
                       ($arg{$c} ne "state" || $cmd !~ m/^set/));
  $cmd.=" $val{$c}" if(defined($val{$c}));
  return ($cmd, $c);
}

#####################
# create FWA_rooms && FWA_types
sub
FWA_updateHashes()
{
  #################
  # Make a room  hash
  %FWA_rooms = ();
  foreach my $d (keys %defs ) {
    next if(IsIgnored($d));
    foreach my $r (split(",", AttrVal($d, "room", "Unsorted"))) {
      $FWA_rooms{$r}{$d} = 1;
    }
  }

  ###############
  # Needed for type sorting
  %FWA_types = ();
  foreach my $d (sort keys %defs ) {
    next if(IsIgnored($d));
    my $t = AttrVal($d, "subType", $defs{$d}{TYPE});
    $t = AttrVal($d, "model", $t) if($t && $t eq "unknown"); # RKO: ???
    $FWA_types{$d} = $t;
  }

  $FWA_room = AttrVal($FWA_detail, "room", "Unsorted") if($FWA_detail);
}

##############################
sub
FWA_makeTable($$$@)
{
  my($title, $name, $hash, $cmd) = (@_);

  return if(!$hash || !int(keys %{$hash}));
  my $class = lc($title);
  $class =~ s/[^A-Za-z]/_/g;
  FWA_pO "<div class='makeTable wide'>";
  FWA_pO $title;
  FWA_pO "<table class=\"block wide $class\">";
  my $si = AttrVal("global", "showInternalValues", 0);

  my $row = 1;
  foreach my $n (sort keys %{$hash}) {
    next if(!$si && $n =~ m/^\./);      # Skip "hidden" Values
    my $val = $hash->{$n};
    $val = "" if(!defined($val));

    $val = $hash->{$n}{NAME}    # Exception
        if($n eq "IODev" && ref($val) eq "HASH" && defined($hash->{$n}{NAME}));

    my $r = ref($val);
    next if($r && ($r ne "HASH" || !defined($hash->{$n}{VAL})));

    FWA_pF "<tr class=\"%s\">", ($row&1)?"odd":"even";
    $row++;

    if($n eq "DEF" && !$FWA_hiddenroom{input}) {
      FWA_makeEdit($name, $n, $val);

    } else {
      if( $title eq "Attributes" ) {
        FWA_pO "<td><div class=\"dname\">".
                "<a onClick='FWA_querySetSelected(\"sel.attr$name\",\"$n\")'>".
              "$n</a></div></td>";
      } else {
         FWA_pO "<td><div class=\"dname\">$n</div></td>";
      }

      if(ref($val)) { #handle readings
        my ($v, $t) = ($val->{VAL}, $val->{TIME});
        $v = FWA_htmlEscape($v);
        if($FWA_ss) {
          $t = ($t ? "<br><div class=\"tiny\">$t</div>" : "");
          FWA_pO "<td><div class=\"dval\">$v$t</div></td>";
        } else {
          $t = "" if(!$t);
          FWA_pO "<td><div informId=\"$name-$n\">$v</div></td>";
          FWA_pO "<td><div informId=\"$name-$n-ts\">$t</div></td>";
        }
      } else {
        $val = FWA_htmlEscape($val);

        # if possible provide som links
        if ($n eq "room"){
          FWA_pO "<td><div class=\"dval\">".
                join(",", map { FWA_pH("room=$_",$_,0,"",1,1) } split(",",$val)).
                "</div></td>";

        } elsif ($n eq "webCmd"){
          my $lc = "detail=$name&cmd.$name=set $name";
          FWA_pO "<td><div name=\"$name-$n\" class=\"dval\">".
                  join(":", map {FWA_pH("$lc $_",$_,0,"",1,1)} split(":",$val) ).
                "</div></td>";

        } elsif ($n =~ m/^fp_(.*)/ && $defs{$1}){ #special for Floorplan
          FWA_pH "detail=$1", $val,1;

        } else {
           FWA_pO "<td><div class=\"dval\">".
                   join(",", map { ($_ ne $name && $defs{$_}) ?
                     FWA_pH( "detail=$_", $_ ,0,"",1,1) : $_ } split(",",$val)).
                 "</div></td>";
        }
      }

    }

    FWA_pH "cmd.$name=$cmd $name $n&amp;detail=$name", $cmd, 1
        if($cmd && !$FWA_ss);
    FWA_pO "</tr>";
  }
  FWA_pO "</table>";
  FWA_pO "</div>";

}

##############################
# Used only for set or attr lists.
sub
FWA_makeSelect($$$$)
{
  my ($d, $cmd, $list,$class) = @_;
  return if(!$list || $FWA_hiddenroom{input});
  my @al = sort map { s/:.*//;$_ } split(" ", $list);

  my $selEl = (defined($al[0]) ? $al[0] : " ");
  $selEl = $1 if($list =~ m/([^ ]*):slider,/); # promote a slider if available
  $selEl = "room" if($list =~ m/room:/);

  FWA_pO "<div class='makeSelect'>";
  FWA_pO "<form method=\"$FWA_formmethod\" ".
                "action=\"$FWA_ME$FWA_subdir\" autocomplete=\"off\">";
  FWA_pO FWA_hidden("detail", $d);
  FWA_pO FWA_hidden("dev.$cmd$d", $d);
  FWA_pO FWA_submit("cmd.$cmd$d", $cmd, $class);
  FWA_pO "<div class=\"$class downText\">&nbsp;$d&nbsp;</div>";
  FWA_pO FWA_select("sel.$cmd$d","arg.$cmd$d", \@al, $selEl, $class,
        "FWA_selChange(this.options[selectedIndex].text,'$list','val.$cmd$d')");
  FWA_pO FWA_textfield("val.$cmd$d", 30, $class);
  # Initial setting
  FWA_pO "<script type=\"text/javascript\">" .
        "FWA_selChange('$selEl','$list','val.$cmd$d')</script>";
  FWA_pO "</form></div>";
}

##############################
sub
FWA_doDetail($)
{
  my ($d) = @_;

  my $h = $defs{$d};
  my $t = $h->{TYPE};
  $t = "MISSING" if(!defined($t));
  FWA_pO "<div id=\"content\">";

  if($FWA_ss) { # FS20MS2 special: on and off, is not the same as toggle
    my $webCmd = AttrVal($d, "webCmd", undef);
    if($webCmd) {
      FWA_pO "<table class=\"webcmd\">";
      foreach my $cmd (split(":", $webCmd)) {
        FWA_pO "<tr>";
        FWA_pH "cmd.$d=set $d $cmd&detail=$d", $cmd, 1, "col1";
        FWA_pO "</tr>";
      }
      FWA_pO "</table>";
    }
  }
  FWA_pO "<table><tr><td>";

  if($modules{$t}{FWA_detailFn}) {
    no strict "refs";
    my $txt = &{$modules{$t}{FWA_detailFn}}($FWA_wname, $d, $FWA_room);
    FWA_pO "$txt<br>" if(defined($txt));
    use strict "refs";
  }

  FWA_pO "<form method=\"$FWA_formmethod\" action=\"$FWA_ME\">";
  FWA_pO FWA_hidden("detail", $d);

  FWA_makeSelect($d, "set", getAllSets($d), "set");
  FWA_makeSelect($d, "get", getAllGets($d), "get");

  FWA_makeTable("Internals", $d, $h);
  FWA_makeTable("Readings", $d, $h->{READINGS});

  my $attrList = getAllAttr($d);
  my $roomList = join(",", sort grep !/ /, keys %FWA_rooms);
  $attrList =~ s/room /room:$roomList /;
  FWA_makeSelect($d, "attr", $attrList,"attr");

  FWA_makeTable("Attributes", $d, $attr{$d}, "deleteattr");
  ## dependent objects
  my @dob;  # dependent objects - triggered by current device
  foreach my $dn (sort keys %defs) {
    next if(!$dn || $dn eq $d);
    my $dh = $defs{$dn};
    if(($dh->{DEF} && $dh->{DEF} =~ m/\b$d\b/) ||
       ($h->{DEF}  && $h->{DEF}  =~ m/\b$dn\b/)) {
      push(@dob, $dn);
    }
  }
  FWA_pO "</form>";
  FWA_makeTableFromArray("Probably associated with", "assoc", @dob,);

  FWA_pO "</td></tr></table>";

  FWA_pH "cmd=style iconFor $d", "Select icon";
  FWA_pH "cmd=style showDSI $d", "Extend devStateIcon";
  FWA_pH "$FWA_ME/docs/commandref.html#${t}", "Device specific help";
  FWA_pO "<br><br>";
  FWA_pO "</div>";

}

##############################
sub
FWA_makeTableFromArray($$@) {
  my ($txt,$class,@obj) = @_;
  if (@obj>0) {
    my $row = 1;
    my $rows = [];
    foreach (sort @obj) {
      my $item = {
       row_class => ($row&1)?"odd":"even",
       link => "detail=$_",
       defs => $defs{$_}{TYPE},
      };
      push($rows, $item);
      $row++;
    }

    return FWA_render("array_table.tx", {
      txt => $txt,
      class => $class,
      rows => $rows,
    });
  }
}

sub
FWA_roomIdx(\@$)
{
  my ($arr,$v) = @_; 
  my ($index) = grep { $v =~ /^$arr->[$_]$/ } 0..$#$arr;
 
  if( !defined($index) ) { 
    $index = 9999;
  } else {
    $index = sprintf( "%03i", $index );
  }
 
  return "$index-$v";
}


##############
# Header, Zoom-Icons & list of rooms at the left.
sub
FWA_menuList($)
{
  my ($cmd) = @_;

  %FWA_hiddenroom = ();
  foreach my $r (split(",",AttrVal($FWA_wname, "hiddenroom", ""))) {
    $FWA_hiddenroom{$r} = 1;
  }

  ##############
  # MENU
  my (@list_extensions, @list_rooms, @list_admin);
  @list_extensions = ();
  @list_rooms = ();
  @list_admin = ();
  
  ########################
  # Show FW Extensions in the menu
  if(defined($data{FWEXT})) {
    my $cnt = 0;
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($h !~ m/HASH/ || !$h->{LINK} || !$h->{NAME});
      next if($FWA_hiddenroom{$h->{NAME}});
      push(@list_extensions, { 
        name => $h->{NAME}, 
        link => $FWA_ME ."/".$h->{LINK} 
       });
      $cnt++;
    }
  }
  $FWA_room = "" if(!$FWA_room);

  my @sortBy = split( " ", AttrVal( $FWA_wname, "sortRooms", "" ) );
  @sortBy = sort keys %FWA_rooms if( scalar @sortBy == 0 );

  ##########################
  # Rooms and other links
  foreach my $r ( sort { FWA_roomIdx(@sortBy,$a) cmp
                         FWA_roomIdx(@sortBy,$b) } keys %FWA_rooms ) {
    next if($r eq "hidden" || $FWA_hiddenroom{$r});
    $r =~ s/</&lt;/g;
    $r =~ s/>/&lt;/g;
    my $roomname = $r;
    $r =~ s/ /%20/g;
    my $roomlink = "$FWA_ME?room=$r";
    push(@list_rooms, { name => $roomname, link => $roomlink, key => $roomname });
  }
  push(@list_rooms, { name => "Everything", link => "$FWA_ME?room=all", key => "all"});
  
  @list_admin = (
     { name => "Commandref",     link => "$FWA_ME/docs/commandref.html", key => "commandref" },
     { name => "Remote doc",     link => "http://fhem.de/fhem.html#Documentation", key => "remotedoc" },
     { name => "Edit files",     link => "$FWA_ME?cmd=style%20list", key => "editfiles" },
     { name => "Select style",   link => "$FWA_ME?cmd=style%20select", key => "selectstyle" },
     { name => "Event monitor",  link => "$FWA_ME?cmd=style%20eventMonitor", key => "eventmonitor" },
  );

  my $lfn = "Logfile";
  if($defs{$lfn}) { # Add the current Logfile to the list if defined
    my @l = FWA_fileList($defs{$lfn}{logfile});
    my $fn = pop @l;
    unshift(\@list_admin, {name => "Logfile", link => "$FWA_ME/FileLog_logWrapper?dev=$lfn&type=text&file=$fn"});
  }
  
  my $data = {
    admin => \@list_admin,
    extensions => \@list_extensions,
    rooms => \@list_rooms,
  };
  return $data;
}

########################
# Show the overview of devices in one room
# room can be a room, all or Unsorted
sub
FWA_roomDetail()
{
  return if(!$FWA_room);
  
  %FWA_hiddengroup = ();
  foreach my $r (split(",",AttrVal($FWA_wname, "hiddengroup", ""))) {
    $FWA_hiddengroup{$r} = 1;
  }

  my $rf = ($FWA_room ? "&amp;room=$FWA_room" : ""); # stay in the room

  # array of all device names in the room (exception weblinks without group
  # attribute)
  my @devs= grep { ($FWA_rooms{$FWA_room}{$_}||$FWA_room eq "all") &&
                      !IsIgnored($_) } keys %defs;
  my (%group, @atEnds, %usuallyAtEnd);
  foreach my $dev (@devs) {
    if($modules{$defs{$dev}{TYPE}}{FWA_atPageEnd}) {
      $usuallyAtEnd{$dev} = 1;
      if(!AttrVal($dev, "group", undef)) {
        push @atEnds, $dev;
        next;
      }
    }
    foreach my $grp (split(",", AttrVal($dev, "group", $FWA_types{$dev}))) {
      next if($FWA_hiddengroup{$grp}); 
      $group{$grp}{$dev} = 1;
    }
  }

  # row counter
  my $row=1;
  my %extPage = ();

  my ($columns, $maxc) = FWA_parseColumns();
  my %groupedDevices = ();

  foreach my $g (sort keys %group) {
    next if($maxc != -1 && (!$columns->{$g}));

    my @deviceList = ();    
    foreach my $d (sort { lc(AttrVal($a,"sortby",AttrVal($a,"alias",$a))) cmp
                          lc(AttrVal($b,"sortby",AttrVal($b,"alias",$b))) }
                   keys %{$group{$g}}) {
      my $type = $defs{$d}{TYPE};
      my $class = ($row&1)?"odd":"even";
      my $devName = AttrVal($d, "alias", $d);
      my $icon = AttrVal($d, "icon", "");
      $icon = FWA_makeImage($icon,$icon,"icon") . "&nbsp;" if($icon);
      my $hiddenroom = $FWA_hiddenroom{detail};
             
      $row++;

      my ($allSets, $cmdlist, $devicestate, $link, $style) = FWA_devState($d, $rf, \%extPage);
      my $colSpan = ($usuallyAtEnd{$d} ? '2' : '');

      ######
      # Commands, slider, dropdown
      my $htmlCmdList = [];
      foreach my $cmd (split(":", $cmdlist)) {
        my $htmlTxt;
        my @c = split(' ', $cmd);
        if($allSets && $allSets =~ m/$c[0]:([^ ]*)/) {
          my $values = $1;
          foreach my $fn (sort keys %{$data{webCmdFn}}) {
            no strict "refs";
            $htmlTxt = &{$data{webCmdFn}{$fn}}($FWA_wname,
                                               $d, $FWA_room, $cmd, $values);
            use strict "refs";
            last if(defined($htmlTxt));
          }
        }
        if($htmlTxt) {
         push($htmlCmdList, mark_raw($htmlTxt));
        } else {
          #FWA_pH "cmd.$d=set $d $cmd$rf", $cmd, 1, "col3"; #TODO: SOLVE THIS
        }
      }
        
      
      my $device = {
        device => $d,
        type => $type,
        class => $class,
        link => $link,
        style => $style,
        name => $devName,
        state => $devicestate,
        icon => mark_raw($icon),
        hiddenroom => $hiddenroom,
        allSets => $allSets,
        htmlCmdList => $htmlCmdList,
      };
      push(@deviceList, $device);
    }
    if(@deviceList) {
      Log 1, $g;
      $groupedDevices{ $g } = \@deviceList;
    }
  }

  # Now the "atEnds"
  foreach my $d (sort { lc(AttrVal($a, "sortby", AttrVal($a,"alias",$a))) cmp
                        lc(AttrVal($b, "sortby", AttrVal($b,"alias",$b))) }
                   @atEnds) {
    no strict "refs";
    my $html = &{$modules{$defs{$d}{TYPE}}{FWA_summaryFn}}($FWA_wname, $d, 
                                                        $FWA_room, \%extPage);
    use strict "refs";
    push(@atEnds, $html);
  }

  return FWA_render("room.tx", {
    groupedDevices => \%groupedDevices,
    atEnds => \@atEnds,
    rf => $rf,
    roomname => $FWA_room,
  });
}

sub
FWA_parseColumns()
{
  my %columns;
  my $colNo = -1;

  foreach my $roomgroup (split("[ \t\r\n]+", AttrVal($FWA_wname,"column",""))) {
    my ($room, $groupcolumn)=split(":",$roomgroup);
    last if(!defined($room) || !defined($groupcolumn));
    next if($room ne $FWA_room);
    $colNo = 1;
    foreach my $groups (split(/\|/,$groupcolumn)) {
      foreach my $group (split(",",$groups)) {
        $columns{$group} = $colNo;
      }
      $colNo++;
    }
  }
  return (\%columns, $colNo);
}


#################
# return a sorted list of actual files for a given regexp
sub
FWA_fileList($)
{
  my ($fname) = @_;
  $fname =~ m,^(.*)/([^/]*)$,; # Split into dir and file
  my ($dir,$re) = ($1, $2);
  return if(!$re);
  $dir =~ s/%L/$attr{global}{logdir}/g if($dir =~ m/%/ && $attr{global}{logdir}); # %L present and log directory defined
  $re =~ s/%./[A-Za-z0-9]*/g;    # logfile magic (%Y, etc)
  my @ret;
  return @ret if(!opendir(DH, $dir));
  while(my $f = readdir(DH)) {
    next if($f !~ m,^$re$,);
    push(@ret, $f);
  }
  closedir(DH);
  return sort @ret;
}


###################################
# Stream big files in chunks, to avoid bloating ourselves.
# This is a "terminal" function, no data can be appended after it is called.
sub
FWA_outputChunk($$$)
{
  my ($c, $buf, $d) = @_;
  $buf = $d->deflate($buf) if($d);
  print $c sprintf("%x\r\n", length($buf)), $buf, "\r\n" if(length($buf));
}

sub
FWA_returnFileAsStream($$$$$)
{
  my ($path, $suffix, $type, $doEsc, $cacheable) = @_;

  my $etag;
  my $c = $FWA_chash->{CD};

  if($cacheable) {
    #Check for If-None-Match header (ETag)
    my @if_none_match_lines = grep /If-None-Match/, @FWA_httpheader;
    my $if_none_match = undef;
    if(@if_none_match_lines) {
      $if_none_match = $if_none_match_lines[0];
      $if_none_match =~ s/If-None-Match: \"(.*)\"/$1/;
    }

    $etag = (stat($path))[9]; #mtime
    if(defined($etag) && defined($if_none_match) && $etag eq $if_none_match) {
      print $c "HTTP/1.1 304 Not Modified\r\n",
        $FWA_headercors, "\r\n";
      return -1;
    }
  }

  if(!open(FH, $path)) {
    Log3 $FWA_wname, 2, "FHEMWEBAPP $FWA_wname $path: $!";
    FWA_pO "<div id=\"content\">$path: $!</div>";
    return 0;
  }
  binmode(FH) if($type !~ m/text/); # necessary for Windows

  $etag = defined($etag) ? "ETag: \"$etag\"\r\n" : "";
  my $expires = $cacheable ? ("Expires: ".gmtime(time()+900)." GMT\r\n"): "";
  my $compr = ((int(@FWA_enc) == 1 && $FWA_enc[0] =~ m/gzip/) && $FWA_use_zlib) ?
                "Content-Encoding: gzip\r\n" : "";
  print $c "HTTP/1.1 200 OK\r\n",
           $compr, $expires, $FWA_headercors, $etag,
           "Transfer-Encoding: chunked\r\n",
           "Content-Type: $type; charset=$FWA_encoding\r\n\r\n";

  my $d = Compress::Zlib::deflateInit(-WindowBits=>31) if($compr);
  FWA_outputChunk($c, $FWA_RET, $d);
  my $buf;
  while(sysread(FH, $buf, 2048)) {
    if($doEsc) { # FileLog special
      $buf =~ s/</&lt;/g;
      $buf =~ s/>/&gt;/g;
    }
    FWA_outputChunk($c, $buf, $d);
  }
  close(FH);
  FWA_outputChunk($c, $suffix, $d);

  if($compr) {
    $buf = $d->flush();
    print $c sprintf("%x\r\n", length($buf)), $buf, "\r\n" if($buf);
  }
  print $c "0\r\n\r\n";
  return -1;
}


##################
sub
FWA_fatal($)
{
  my ($msg) = @_;
  FWA_pO "<html><body>$msg</body></html>";
}

##################
sub
FWA_hidden($$)
{
  my ($name, $value) = @_;
  return FWA_render("input_hidden.tx", { name => $name, value => $value }); #<input type=\"hidden\" name=\"$n\" value=\"$v\"/>";
}

##################
# Generate a select field with option list
sub
FWA_select($$$$$@)
{
  my ($id, $n, $va, $def, $class, $jSelFn) = @_;
  $jSelFn = ($jSelFn ? "onchange=\"$jSelFn\"" : "");
  $id = ($id ? "id=\"$id\" informId=\"$id\"" : "");
  my $s = "<select $jSelFn $id name=\"$n\" class=\"$class\">";
  foreach my $v (@{$va}) {
    if($def && $v eq $def) {
      $s .= "<option selected=\"selected\" value='$v'>$v</option>\n";
    } else {
      $s .= "<option value='$v'>$v</option>\n";
    }
  }
  $s .= "</select>";
  return $s;
}

##################
sub
FWA_textfieldv($$$$)
{
  my ($n, $z, $class, $value) = @_;
  my $v;
  $v=" value=\"$value\"" if(defined($value));
  return if($FWA_hiddenroom{input});
  my $s = "<input type=\"text\" name=\"$n\" class=\"$class\" size=\"$z\"$v/>";
  return $s;
}

sub
FWA_textfield($$$)
{
  return FWA_textfieldv($_[0], $_[1], $_[2], "");
}

##################
sub
FWA_submit($$@)
{
  my ($n, $v, $class) = @_;
  $class = ($class ? "class=\"$class\"" : "");
  my $s ="<input type=\"submit\" name=\"$n\" value=\"$v\" $class/>";
  return $s;
}

##################
sub
FWA_displayFileList($@)
{
  my ($heading,@files)= @_;
  my $hid = lc($heading);
  $hid =~ s/[^A-Za-z]/_/g;
  FWA_pO "<div class=\"fileList $hid\">$heading</div>";
  FWA_pO "<table class=\"block fileList\">";
  my $row = 0;
  foreach my $f (@files) {
    FWA_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
    FWA_pH "cmd=style edit $f", $f, 1;
    FWA_pO "</tr>";
    $row = ($row+1)%2;
  }
  FWA_pO "</table>";
  FWA_pO "<br>";
} 

##################
sub
FWA_fileNameToPath($)
{
  my $name = shift;

  $attr{global}{configfile} =~ m,([^/]*)$,;
  my $cfgFileName = $1;
  if($name eq $cfgFileName) {
    return $attr{global}{configfile};
  } elsif($name =~ m/.*(css|svg)$/) {
    return "$FWA_appdir/$name";
  } elsif($name =~ m/.*gplot$/) {
    return "$FWA_gplotdir/$name";
  } else {
    return "$MWA_dir/$name";
  }
}

##################
# List/Edit/Save css and gnuplot files
sub
FWA_style($$)
{
  my ($cmd, $msg) = @_;
  my @a = split(" ", $cmd);

  my $start = "<div id=\"content\"><table><tr><td>";
  my $end   = "</td></tr></table></div>";
  
  if($a[1] eq "list") {
    $attr{global}{configfile} =~ m,([^/]*)$,;
    my @cfg = ($1,);
    my @modules = FWA_fileList("$MWA_dir/^(.*sh|[0-9][0-9].*Util.*pm|.*cfg|.*holiday"."|.*layout)\$");
    my @styles = FWA_fileList("$FWA_appdir/css/^.*(css|svg)\$");
    my @gplots = FWA_fileList("$FWA_gplotdir/^.*gplot\$");
    my @groups = ({
          name => "FHEM Config file",
          items => \@cfg,
        },{
          name => "Own modules and helper files",
          items => \@modules,
        },{
          name => "Styles & SVGs",
          items => \@styles,
        },{
          name => "GPLOT Files",
          items => \@gplots,
        });
        
    my $data = {
      msg => $msg,
      groups => \@groups,
      baseuri => "$FWA_ME$FWA_subdir",
    };

    return FWA_render("style_list.tx", $data);

  } elsif($a[1] eq "select") {
    my @fl = grep { $_ !~ m/(floorplan|dashboard)/ } FWA_fileList("$FWA_appdir/.*style.css");
    FWA_pO "$start<table class=\"block fileList\">";
    my $row = 0;
    foreach my $file (@fl) {
      next if($file =~ m/svg_/);
      $file =~ s/style.css//;
      $file = "default" if($file eq "");
      FWA_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      FWA_pH "cmd=style set $file", "$file", 1;
      FWA_pO "</tr>";
      $row = ($row+1)%2;
    }
    FWA_pO "</table>$end";

  } elsif($a[1] eq "set") {
    if($a[2] eq "default") {
      CommandDeleteAttr(undef, "$FWA_wname stylesheetPrefix");
    } else {
      CommandAttr(undef, "$FWA_wname stylesheetPrefix $a[2]");
    }
    FWA_pO "${start}Reload the page in the browser.$end";

  } elsif($a[1] eq "edit") {
    my $fileName = $a[2]; 
    $fileName =~ s,.*/,,g;        # Little bit of security
    my $filePath = FWA_fileNameToPath($fileName);
    my $error = "";
    if(!open(FH, $filePath)) {
      return FWA_render("error.tx", { error => "$filePath: $!"});
    }
    my $data = join("", <FH>);
    close(FH);

    $data =~ s/&/&amp;/g;
    
    return FWA_render("style_edit.tx", {
      file => $fileName,
      text => $data,
      formmethod => $FWA_formmethod,
      msg => $msg,
    });
  } elsif($a[1] eq "save") {
    my $fileName = $a[2];
    $fileName = $FWA_webArgs{saveName}
        if($FWA_webArgs{saveAs} && $FWA_webArgs{saveName});
    $fileName =~ s,.*/,,g;        # Little bit of security
    my $filePath = FWA_fileNameToPath($fileName);

    if(!open(FH, ">$filePath")) {
      return FWA_render("error.tx", { error => "$filePath: $!"});
    }
    $FWA_data =~ s/\r//g if($^O !~ m/Win/);
    binmode (FH);
    print FH $FWA_data;
    close(FH);

    my $ret = FWA_fC("rereadcfg") if($filePath eq $attr{global}{configfile});
    $ret = FWA_fC("reload $fileName") if($fileName =~ m,\.pm$,);
    $ret = ($ret ? "$ret" : "Saved the file $fileName");
    return FWA_style("style edit $fileName", $ret);

  } elsif($a[1] eq "iconFor") {
    FWA_iconTable("iconFor", "icon", "style setIF $a[2] %s", undef);

  } elsif($a[1] eq "setIF") {
    FWA_fC("attr $a[2] icon $a[3]");
    FWA_doDetail($a[2]);

  } elsif($a[1] eq "showDSI") {
    FWA_iconTable("devStateIcon", "",
                 "style addDSI $a[2] %s", "Enter value/regexp for STATE");

  } elsif($a[1] eq "addDSI") {
    my $dsi = AttrVal($a[2], "devStateIcon", "");
    $dsi .= " " if($dsi);
    FWA_fC("attr $a[2] devStateIcon $dsi$FWA_data:$a[3]");
    FWA_doDetail($a[2]);

  } elsif($a[1] eq "eventMonitor") {
    FWA_pO "<script type=\"text/javascript\" src=\"$FWA_ME/pgm2/console.js\">".
          "</script>";
    FWA_pO "<div id=\"content\">";
    FWA_pO "<div id=\"console\">";
    FWA_pO "Events:<br>\n";
    FWA_pO "</div>";
    FWA_pO "</div>";

  }

}

sub
FWA_iconTable($$$$)
{
  my ($name, $class, $cmdFmt, $textfield) = @_;

  my %icoList = ();
  foreach my $style (@FWA_iconDirs) {
    foreach my $imgName (sort keys %{$FWA_icons{$style}}) {
      $imgName =~ s/\.[^.]*$//; # Cut extension
      next if(!$FWA_icons{$style}{$imgName}); # Dont cut it twice: FS20.on.png
      next if($FWA_icons{$style}{$imgName} !~ m/$imgName/); # Skip alias
      next if($imgName=~m+^(weather/|shutter.*big|fhemicon|favicon|ws_.*_kl)+);
      next if($imgName=~m+^(dashboardicons)+);
      $icoList{$imgName} = 1;
    }
  }

  FWA_pO "<div id=\"content\">";
  FWA_pO "<form method=\"$FWA_formmethod\">";
  if($textfield) {
    FWA_pO "$textfield:&nbsp;".FWA_textfieldv("data",20,"iconTable",".*")."<br>";
  }
  foreach my $i (sort keys %icoList) {
    FWA_pF "<button title='%s' type='submit' class='dist' name='cmd' ".
              "value='$cmdFmt'>%s</button>", $i, $i, FWA_makeImage($i,$i,$class);
  }
  FWA_pO "</form>";
  FWA_pO "</div>";
}

##################
# print (append) to output
sub
FWA_pO(@)
{
  my $arg = shift;
  return if(!defined($arg));
  $FWA_RET .= $arg;
  $FWA_RET .= "\n";
}

#################
# add href
sub
FWA_pH(@)
{
  my ($link, $txt, $td, $class, $doRet,$nonl) = @_;
  my $ret;

  $link = ($link =~ m,^/,) ? $link : "$FWA_ME$FWA_subdir?$link";
  
  # Using onclick, as href starts safari in a webapp.
  # Known issue: the pointer won't change
  if($FWA_ss || $FWA_tp) { 
    $ret = "<a onClick=\"location.href='$link'\">$txt</a>";
  } else {
    $ret = "<a href=\"$link\">$txt</a>";
  }

  #actually 'div' should be removed if no class is defined
  #  as I can't check all code for consistancy I add nonl instead
  $class = ($class)?" class=\"$class\"":"";
  $ret = "<div$class>$ret</div>" if (!$nonl);

  $ret = "<td>$ret</td>" if($td);
  return $ret if($doRet);
  FWA_pO $ret;
}

#################
# href without class/div, returned as a string
sub
FWA_pHPlain(@)
{
  my ($link, $txt, $td) = @_;

  $link = "?$link" if($link !~ m+^/+);
  my $ret = "";
  $ret .= "<td>" if($td);
  if($FWA_ss || $FWA_tp) {
    $ret .= "<a onClick=\"location.href='$FWA_ME$FWA_subdir$link'\">$txt</a>";
  } else {
    $ret .= "<a href=\"$FWA_ME$FWA_subdir$link\">$txt</a>";
  }
  $ret .= "</td>" if($td);
  return $ret;
}


sub
FWA_makeImage(@)
{
  my ($name, $txt, $class)= @_;

  $txt = $name if(!defined($txt));
  $class = "" if(!$class);
  $class = "$class $name";
  $class =~ s/\./_/g;
  $class =~ s/@/ /g;

  my $p = FWA_iconPath($name);
  return $name if(!$p);
  if($p =~ m/\.svg$/i) {
    if(open(FH, "$FWA_icondir/$p")) {
      <FH>; <FH>; <FH>; # Skip the first 3 lines;
      my $data = join("", <FH>);
      close(FH);
      $data =~ s/[\r\n]/ /g;
      $data =~ s/ *$//g;
      $data =~ s/<svg/<svg class="$class"/;
      $name =~ m/(@.*)$/;
      my $col = $1 if($1);
      if($col) {
        $col =~ s/@//;
        $col = "#$col" if($col =~ m/^([A-F0-9]{6})$/);
        $data =~ s/fill="#000000"/fill="$col"/g;
        $data =~ s/fill:#000000/fill:$col/g;
      } else {
        $data =~ s/fill="#000000"//g;
        $data =~ s/fill:#000000//g;
      }
      return $data;
    } else {
      return $name;
    }
  } else {
    return FWA_render("image.tx", {
      class => $class,
      src => "$FWA_ME/images/$p",
      txt => "$txt",
    });
  }
}

####
sub
FWA_IconURL($) 
{
  my ($name)= @_;
  return "$FWA_ME/icons/$name";
}

##################
# print formatted
sub
FWA_pF($@)
{
  my $fmt = shift;
  $FWA_RET .= sprintf $fmt, @_;
}

##################
# fhem command
sub
FWA_fC($@)
{
  my ($cmd, $unique) = @_;
  my $ret;
  if($unique) {
    $ret = AnalyzeCommand($FWA_chash, $cmd);
  } else {
    $ret = AnalyzeCommandChain($FWA_chash, $cmd);
  }
  return $ret;
}

sub
FWA_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  my $name = $hash->{NAME};
  my $sP = "stylesheetPrefix";
  my $retMsg;

  if($a[0] eq "set" && $a[2] eq "HTTPS") {
    TcpServer_SetSSL($hash);
  }

  if($a[0] eq "set") { # Converting styles
   if($a[2] eq "smallscreen" || $a[2] eq "touchpad") {
     $attr{$name}{$sP} = $a[2];
     $retMsg="$name: attribute $a[2] deprecated, converted to $sP";
     $a[3] = $a[2]; $a[2] = $sP;
   }
  }
  if($a[2] eq $sP) {
    # AttrFn is called too early, we have to set/del the attr here
    if($a[0] eq "set") {
      $attr{$name}{$sP} = (defined($a[3]) ? $a[3] : "default");
      FWA_readIcons($attr{$name}{$sP});
    } else {
      delete $attr{$name}{$sP};
    }
  }

  if($a[2] eq "iconPath" && $a[0] eq "set") {
    foreach my $pe (split(":", $a[3])) {
      $pe =~ s+\.\.++g;
      FWA_readIcons($pe);
    }
  }

  return $retMsg;
}


# recursion starts at $FWA_icondir/$dir
# filenames are relative to $FWA_icondir
sub
FWA_readIconsFrom($$)
{
  my ($dir,$subdir)= @_;

  my $ldir = ($subdir ? "$dir/$subdir" : $dir);
  my @entries;
  if(opendir(DH, "$FWA_icondir/$ldir")) {
    @entries= sort readdir(DH); # assures order: .gif  .ico  .jpg  .png .svg
    closedir(DH);
  }

  foreach my $entry (@entries) {
    if( -d "$FWA_icondir/$ldir/$entry" ) {  # directory -> recurse
      FWA_readIconsFrom($dir, $subdir ? "$subdir/$entry" : $entry)
        unless($entry eq "." || $entry eq ".." || $entry eq ".svn");

    } else {
      if($entry =~ m/^iconalias.txt$/i && open(FH, "$FWA_icondir/$ldir/$entry")){
        while(my $l = <FH>) {
          chomp($l);
          my @a = split(" ", $l);
          next if($l =~ m/^#/ || @a < 2);
          $FWA_icons{$dir}{$a[0]} = $a[1];
        }
        close(FH);
      } elsif($entry =~ m/(gif|ico|jpg|png|jpeg|svg)$/i) {
        my $filename = $subdir ? "$subdir/$entry" : $entry;
        $FWA_icons{$dir}{$filename} = $filename;

        my $tag = $filename;     # Add it without extension too
        $tag =~ s/\.[^.]*$//;
        $FWA_icons{$dir}{$tag} = $filename;
      }
    }
  }
  $FWA_icons{$dir}{""} = 1; # Do not check empty directories again.
}

sub
FWA_readIcons($)
{
  my ($dir)= @_;
  return if($FWA_icons{$dir});
  FWA_readIconsFrom($dir, "");
}


# check if the icon exists, and if yes, returns its "logical" name;
sub
FWA_iconName($)
{
  my ($name)= @_;
  $name =~ s/@.*//;
  foreach my $pe (@FWA_iconDirs) {
    return $name if($pe && $FWA_icons{$pe} && $FWA_icons{$pe}{$name});
  }
  return undef;
}

# returns the physical absolute path relative for the logical path
# examples:
#   FS20.on       -> dark/FS20.on.png
#   weather/sunny -> default/weather/sunny.gif
sub
FWA_iconPath($)
{
  my ($name) = @_;
  $name =~ s/@.*//;
  foreach my $pe (@FWA_iconDirs) {
    return "$pe/$FWA_icons{$pe}{$name}"
        if($pe && $FWA_icons{$pe} && $FWA_icons{$pe}{$name});
  }
  return undef;
}

sub
FWA_dev2image($;$)
{
  my ($name, $state) = @_;
  my $d = $defs{$name};
  return "" if(!$name || !$d);

  my $type = $d->{TYPE};
  $state = $d->{STATE} if(!defined($state));
  return "" if(!$type || !defined($state));

  my $model = $attr{$name}{model} if(defined($attr{$name}{model}));

  my (undef, $rstate) = ReplaceEventMap($name, [undef, $state], 0);

  my ($icon, $rlink);
  my $devStateIcon = AttrVal($name, "devStateIcon", undef);
  if(defined($devStateIcon) && $devStateIcon =~ m/^{.*}$/) {
    my ($html, $link) = eval $devStateIcon;
    Log3 $FWA_wname, 1, "devStateIcon $name: $@" if($@);
    return ($html, $link, 1) if(defined($html) && $html =~ m/^<.*>$/s);
    $devStateIcon = $html;
  }

  if(defined($devStateIcon)) {
    my @list = split(" ", $devStateIcon);
    foreach my $l (@list) {
      my ($re, $iconName, $link) = split(":", $l, 3);
      if(defined($re) && $state =~ m/^$re$/) {
        if($iconName eq "") {
          $rlink = $link;
          last;
        }
        if(defined(FWA_iconName($iconName)))  {
          return ($iconName, $link, 0);
        } else {
          return ($state, $link, 1);
        }
      }
    }
  }

  $state =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"

  $icon = FWA_iconName("$name.$state")   if(!$icon);           # lamp.Aus.png
  $icon = FWA_iconName("$name.$rstate")  if(!$icon);           # lamp.on.png
  $icon = FWA_iconName($name)            if(!$icon);           # lamp.png
  $icon = FWA_iconName("$model.$state")  if(!$icon && $model); # fs20st.off.png
  $icon = FWA_iconName($model)           if(!$icon && $model); # fs20st.png
  $icon = FWA_iconName("$type.$state")   if(!$icon);           # FS20.Aus.png
  $icon = FWA_iconName("$type.$rstate")  if(!$icon);           # FS20.on.png
  $icon = FWA_iconName($type)            if(!$icon);           # FS20.png
  $icon = FWA_iconName($state)           if(!$icon);           # Aus.png
  $icon = FWA_iconName($rstate)          if(!$icon);           # on.png
  return ($icon, $rlink, 0);
}

sub
FWA_makeEdit($$$)
{
  # my ($name, $n, $val) = @_;
  # $val =~ s,\\\n,\n,g;
  # my $eval = $val;
  # $eval = "<pre>$eval</pre>" if($eval =~ m/\n/);
  # my $cmd = "modify";
  # my $ncols = $FWA_ss ? 30 : 60;

  # my $html = FWA_render("edit.tx", {
    # n => $n,
    # eval => mark_raw($eval),
    # formmethod => $FWA_formmethod,
    # cmdname => "$cmd.$name",
    # submit_name => "cmd.$cmd$name",
    # submit_value= => "$cmd $name"
  # });
  # return $html;
}

sub
FWA_roomStatesForInform($)
{
  my ($me) = @_;
  return "" if($me->{inform}{type} !~ m/status/);

  my %extPage = ();
  my @data;
  foreach my $dn (keys %{$me->{inform}{devices}}) {
    next if(!defined($defs{$dn}));
    my $t = $defs{$dn}{TYPE};
    next if(!$t || $modules{$t}{FWA_atPageEnd});
    my ($allSet, $cmdlist, $txt) = FWA_devState($dn, "", \%extPage);
    if($defs{$dn} && $defs{$dn}{STATE} && $defs{$dn}{TYPE} ne "weblink") {
      push @data, "$dn<<$defs{$dn}{STATE}<<$txt";
    }
  }
  my $data = join("\n", map { s/\n/ /gm; $_ } @data)."\n";
  return $data;
}

sub
FWA_Notify($$)
{
  my ($ntfy, $dev) = @_;

  my $h = $ntfy->{inform};
  return undef if(!$h);

  my $dn = $dev->{NAME};
  return undef if(!$h->{devices}{$dn});

  my @data;
  my %extPage;

  if($h->{type} =~ m/status/) {
    # Why is saving this stuff needed? FLOORPLAN?
    my @old = ($FWA_wname, $FWA_ME, $FWA_ss, $FWA_tp, $FWA_subdir);
    $FWA_wname = $ntfy->{SNAME};
    $FWA_ME = "/" . AttrVal($FWA_wname, "webname", "fhem");
    $FWA_subdir = "";
    $FWA_sp = AttrVal($FWA_wname, "stylesheetPrefix", 0);
    $FWA_ss = ($FWA_sp =~ m/smallscreen/);
    $FWA_tp = ($FWA_sp =~ m/smallscreen|touchpad/);
    @FWA_iconDirs = grep { $_ } split(":", AttrVal($FWA_wname, "iconPath",
                                "$FWA_sp:default:fhemSVG:openautomation"));
    if($h->{iconPath}) {
      unshift @FWA_iconDirs, $h->{iconPath};
      FWA_readIcons($h->{iconPath});
    }

    my ($allSet, $cmdlist, $txt) = FWA_devState($dn, "", \%extPage);
    ($FWA_wname, $FWA_ME, $FWA_ss, $FWA_tp, $FWA_subdir) = @old;
    push @data, "$dn<<$dev->{STATE}<<$txt";

    #Add READINGS
    if($dev->{CHANGED}) {    # It gets deleted sometimes (?)
      my $tn = TimeNow();
      my $max = int(@{$dev->{CHANGED}});
      for(my $i = 0; $i < $max; $i++) {
        if( $dev->{CHANGED}[$i] !~ /: /) {
          next; #ignore 'set' commands
        }
        my ($readingName,$readingVal) = split(": ",$dev->{CHANGED}[$i],2);
        push @data, "$dn-$readingName<<$readingVal<<$readingVal";
        push @data, "$dn-$readingName-ts<<$tn<<$tn";
      }
    }
  }

  if($h->{type} =~ m/raw/) {
    if($dev->{CHANGED}) {    # It gets deleted sometimes (?)
      my $tn = TimeNow();
      if($attr{global}{mseclog}) {
        my ($seconds, $microseconds) = gettimeofday();
        $tn .= sprintf(".%03d", $microseconds/1000);
      }
      my $max = int(@{$dev->{CHANGED}});
      my $dt = $dev->{TYPE};
      for(my $i = 0; $i < $max; $i++) {
        push @data,("$tn $dt $dn ".$dev->{CHANGED}[$i]."<br>");
      }
    }
  }

  addToWritebuffer($ntfy, join("\n", map { s/\n/ /gm; $_ } @data)."\n")
    if(@data);
  return undef;
}

###################
# Compute the state (==second) column
sub
FWA_devState($$@)
{
  my ($d, $rf, $extPage) = @_;

  my ($hasOnOff, $link);

  my $cmdList = AttrVal($d, "webCmd", "");
  my $allSets = getAllSets($d);
  my $state = $defs{$d}{STATE};
  $state = "" if(!defined($state));

  $hasOnOff = ($allSets =~ m/(^| )on(:[^ ]*)?( |$)/ &&
               $allSets =~ m/(^| )off(:[^ ]*)?( |$)/);
  my $txt = $state;
  if(defined(AttrVal($d, "showtime", undef))) {
    my $v = $defs{$d}{READINGS}{state}{TIME};
    $txt = $v if(defined($v));

  } elsif($allSets =~ m/\bdesired-temp:/) {
    $txt = "$1 °C" if($txt =~ m/^measured-temp: (.*)/);      # FHT fix
    $cmdList = "desired-temp" if(!$cmdList);

  } elsif($allSets =~ m/\bdesiredTemperature:/) {
    $txt = ReadingsVal($d, "temperature", "");  # ignores stateFormat!!!
    $txt =~ s/ .*//;
    $txt .= "°C";
    $cmdList = "desiredTemperature" if(!$cmdList);

  } else {
    my ($icon, $isHtml);
    ($icon, $link, $isHtml) = FWA_dev2image($d);
    $txt = ($isHtml ? $icon : FWA_makeImage($icon, $state)) if($icon);
    $link = "cmd.$d=set $d $link" if($link);

  }


  if($hasOnOff) {
    # Have to cover: "on:An off:Aus", "A0:Aus AI:An Aus:off An:on"
    my $on  = ReplaceEventMap($d, "on", 1);
    my $off = ReplaceEventMap($d, "off", 1);
    $link = "cmd.$d=set $d " . ($state eq $on ? $off : $on) if(!$link);
    $cmdList = "$on:$off" if(!$cmdList);

  }

  my $style = AttrVal($d, "devStateStyle", "");
  if($link) { # Have command to execute
    my $room = AttrVal($d, "room", undef);
    if($room) {
      if($FWA_room && $room =~ m/\b$FWA_room\b/) {
        $room = $FWA_room;
      } else {
        $room =~ s/,.*//;
      }
      $link .= "&room=$room";
    }
    
    if(AttrVal($FWA_wname, "longpoll", 1)) {
      $link = "$FWA_ME$FWA_subdir?XHR=1&$link";
      $style .= " longpoll";
    } elsif($FWA_ss || $FWA_tp) {
      $style .= " onclick";
      $link = "$FWA_ME$FWA_subdir?$link$rf";
    } else {
      $link = "$FWA_ME$FWA_subdir?$link$rf";
    }
  }

  my $type = $defs{$d}{TYPE};
  my $sfn = $modules{$type}{FWA_summaryFn};
  if($sfn) {
    if(!defined($extPage)) {
       my %hash;
       $extPage = \%hash;
    }
    no strict "refs";
    my $newtxt = &{$sfn}($FWA_wname, $d, $FWA_room, $extPage);
    use strict "refs";
    $txt = $newtxt if(defined($newtxt)); # As specified
  }

  return ($allSets, $cmdList, mark_raw($txt), $link, $style);
}


sub
FWA_Get($@)
{
  my ($hash, @a) = @_;
  $FWA_wname= $hash->{NAME};

  my $arg = (defined($a[1]) ? $a[1] : "");
  if($arg eq "icon") {
    return "need one icon as argument" if(int(@a) != 3);
    my $icon = FWA_iconPath($a[2]);
    return defined($icon) ? "$FWA_icondir/$icon" : "no such icon";

  } elsif($arg eq "pathlist") {
    return "web server root:      $FWA_dir\n".
           "icon directory:       $FWA_icondir\n".
           "css directory:        $FWA_appdir\n".
           "gplot directory:      $FWA_gplotdir";

  } else {
    return "Unknown argument $arg choose one of icon pathlist:noArg";

  }
}


#####################################
sub
FWA_Set($@)
{
  my ($hash, @a) = @_;
  my %cmd = ("rereadicons" => 1, "clearSvgCache" => 1);

  return "no set value specified" if(@a < 2);
  return ("Unknown argument $a[1], choose one of ".
        join(" ", map { "$_:noArg" } sort keys %cmd))
    if(!$cmd{$a[1]});

  if($a[1] eq "rereadicons") {
    my @dirs = keys %FWA_icons;
    %FWA_icons = ();
    foreach my $d  (@dirs) {
      FWA_readIcons($d);
    }
  }
  if($a[1] eq "clearSvgCache") {
    my $cDir = "$FWA_dir/SVGcache";
    if(opendir(DH, $cDir)) {
      map { my $n="$cDir/$_"; unlink($n) if(-f $n); } readdir(DH);;
      closedir(DH);
    } else {
      return "Can't open $cDir: $!";
    }
  }
  return undef;
}

#####################################
sub
FWA_closeOldClients()
{
  my $now = time();
  foreach my $dev (keys %defs) {
    next if(!$defs{$dev}{TYPE} || $defs{$dev}{TYPE} ne "FHEMWEBAPP" ||
            !$defs{$dev}{LASTACCESS} || $defs{$dev}{inform} ||
            ($now - $defs{$dev}{LASTACCESS}) < 60);
    Log3 $FWA_wname, 4, "Closing connection $dev";
    FWA_Undef($defs{$dev}, "");
    delete $defs{$dev};
  }
  InternalTimer($now+60, "FWA_closeOldClients", 0, 0);
}

sub
FWA_htmlEscape($)
{
  my ($txt) = @_;
  $txt =~ s/</&lt;/g;
  $txt =~ s/>/&gt;/g;
  return $txt;
}

###########################
# Widgets START
sub
FWA_sliderFn($$$$$)
{
  my ($FWA_wname, $d, $FWA_room, $cmd, $values) = @_;

  return undef if($values !~ m/^slider,(.*),(.*),(.*)$/);
  return "" if($cmd =~ m/ /);   # webCmd pct 30 should generate a link
  my ($min,$stp, $max) = ($1, $2, $3);
  my $srf = $FWA_room ? "&room=$FWA_room" : "";
  my $cv = ReadingsVal($d, $cmd, Value($d));
  my $id = ($cmd eq "state") ? "" : "-$cmd";
  $cmd = "" if($cmd eq "state");
  $cv =~ s/.*?([.\-\d]+).*/$1/; # get first number
  $cv = 0 if($cv !~ m/\d/);
  return "<td colspan='2'>".
           "<div class='slider' id='slider.$d$id' min='$min' stp='$stp' ".
                 "max='$max' cmd='$FWA_ME?cmd=set $d $cmd %$srf'>".
             "<div class='handle'>$min</div>".
           "</div>".
           "<script type=\"text/javascript\">".
             "FWA_sliderCreate(document.getElementById('slider.$d$id'),'$cv');".
           "</script>".
         "</td>";
}

sub
FWA_noArgFn($$$$$)
{
  my ($FWA_wname, $d, $FWA_room, $cmd, $values) = @_;

  return undef if($values !~ m/^noArg$/);
  return "";
}

sub
FWA_timepickerFn()
{
  my ($FWA_wname, $d, $FWA_room, $cmd, $values) = @_;

  return undef if($values ne "time");
  return "" if($cmd =~ m/ /);   # webCmd on-for-timer 30 should generate a link
  my $srf = $FWA_room ? "&room=$FWA_room" : "";
  my $cv = ReadingsVal($d, $cmd, Value($d));
  $cmd = "" if($cmd eq "state");
  my $c = "\"$FWA_ME?cmd=set $d $cmd %$srf\"";
  return "<td colspan='2'>".
            "<input name='time.$d' value='$cv' type='text' readonly size='5'>".
            "<input type='button' value='+' onclick='FWA_timeCreate(this,$c)'>".
          "</td>";
}

sub 
FWA_dropdownFn()
{
  my ($FWA_wname, $d, $FWA_room, $cmd, $values) = @_;

  return "" if($cmd =~ m/ /);   # webCmd temp 30 should generate a link
  my @tv = split(",", $values);
  # Hack: eventmap (translation only) should not result in a
  # dropdown.  eventMap/webCmd/etc handling must be cleaned up.
  if(@tv > 1) {
    my $txt;
    if($cmd eq "desired-temp" || $cmd eq "desiredTemperature") {
      $txt = ReadingsVal($d, $cmd, 20);
      $txt =~ s/ .*//;        # Cut off Celsius
      $txt = sprintf("%2.1f", int(2*$txt)/2) if($txt =~ m/[0-9.-]/);
    } else {
      $txt = ReadingsVal($d, $cmd, Value($d));
      $txt =~ s/$cmd //;
    }

    my $select = {
      title => $cmd eq "state" ? "" : "$cmd&nbsp;",
      id => "$d-$cmd",
      name => "val.$d",
      values => \@tv,
      default => $txt,
      class => "dropdown",
    };

    return FWA_render("dropdown.tx", {
        formmethod => $FWA_formmethod,
        device => $d,
        select => $select,
      });
  }
  return "";
}

sub
FWA_textFieldFn($$$$)
{
  my ($FWA_wname, $d, $FWA_room, $cmd, $values) = @_;

  my @args = split("[ \t]+", $cmd);

  return undef if($values !~ m/^textField$/);
  return "" if($cmd =~ m/ /);
  my $srf = $FWA_room ? "&room=$FWA_room" : "";
  my $cv = ReadingsVal($d, $cmd, "");
  my $id = ($cmd eq "state") ? "" : "-$cmd";

  my $c = "$FWA_ME?XHR=1&cmd=setreading $d $cmd %$srf";
  return '<td align="center">'.
           "<div>$cmd:<input id='textField.$d$id' type='text' value='$cv' ".
                        "onChange='textField_setText(this,\"$c\")'></div>".
         '</td>';
}

# Widgets END
###########################

sub 
FWA_ActivateInform()
{
  $FWA_activateInform = 1;
}

1;
