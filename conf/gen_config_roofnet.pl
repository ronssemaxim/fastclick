#!/usr/bin/perl -w

use strict;

use Getopt::Long;



sub usage() {
    print STDERR "usage:
    --dev {e. g. ath0}
    --ssid
    --channel
    --gateway
    --mode {a/b/g}
    --ap ( act as an access point. off by default)
    --txf (enable/disable tx-feedback. on by default)
";
    exit 1;
}

sub mac_addr_from_dev($) {
    my $device = $_[0];
    my $output = `/sbin/ifconfig $device 2>&1`;
    if ($output =~ /^$device: error/) {
        return "";
    }
    my @tmp = split(/\s+/, $output);
    my $mac = $tmp[4];
    $mac =~ s/-/:/g;
    my @hex = split(/:/, $mac);
    
    return uc (join ":", @hex[0 .. 5]);
}




sub mac_addr_to_ip($) {
    my $mac = $_[0];
    my @hex = split(/:/, $mac);
    if (scalar(@hex) != 6) {
        return "0";
    }
    # convert the hex digits to decimals                                            
    my $x = hex($hex[3]);
    my $y = hex($hex[4]);
    my $z = hex($hex[5]);

    return "$x.$y.$z";

}

my $dev;
my $channel = 3;
my $ssid;
my $mode = "g";
my $gateway = 0;
my $ap = 0;
my $txf = 1;
my $interval = 10000;
my $rate_control = "static-2";
GetOptions('device=s' => \$dev,
	   'channel=i' => \$channel,
	   'ssid=s' => \$ssid,
	   'mode=s' => \$mode,
	   'gateway' => \$gateway,
	   'ap!' => \$ap,
	   'txf!' => \$txf,
	   'rate-control=s' => \$rate_control,
	   ) or usage();


if (! defined $dev) {
    if (`/sbin/ifconfig ath0 2>&1` =~ /Device not found/) {
	if (`/sbin/ifconfig wlan0 2>&1` =~ /Device not found/) {
	} else {
	    $dev = "wlan0";
	}
    } else {
	$dev = "ath0";
    }
}


if (! defined $dev) {
    usage();
}


if ($gateway) {
    $gateway = "true";
} else{
    $gateway = "false";
}
if ($dev =~ /wlan/) {
    $mode= "b";
}

my $hostname = `hostname`;
my $wireless_mac = mac_addr_from_dev($dev);
my $suffix;
if ($hostname =~ /rn-pdos(\S+)-wired/) {
    $suffix = "0.0.$1";
    $channel = "11";
} else {
    $suffix = mac_addr_to_ip($wireless_mac);
}



my $srcr_ip = "5." . $suffix;
my $safe_ip = "6." . $suffix;
my $rate_ip = "7." . $suffix;
my $ap_ip = "12." . $suffix;

my $srcr_nm = "255.0.0.0";
my $srcr_net = "5.0.0.0";
my $srcr_bcast = "5.255.255.255";

if (! defined $ssid) {
    $ssid = "roofnet.$srcr_ip";
}
if ($wireless_mac eq "" or 
    $wireless_mac eq "00:00:00:00:00:00") {
    print STDERR "got invalid mac address!";
    exit -1;
}
system "/sbin/ifconfig $dev up";
my $iwconfig = "/home/roofnet/bin/iwconfig";

if (-f "/sbin/iwconfig") {
    $iwconfig = "/sbin/iwconfig";
}

system "$iwconfig $dev mode Ad-Hoc";
system "$iwconfig $dev channel $channel";

if (!($dev =~ /ath/)) {
#    system "/sbin/ifconfig $dev $safe_ip";
#    system "/sbin/ifconfig $dev mtu 1650";
}

if ($dev =~ /wlan/) {
    system "/home/roofnet/bin/prism2_param $dev ptype 6";
    system "/home/roofnet/bin/prism2_param $dev pseudo_ibss 1";
    system "/home/roofnet/bin/prism2_param $dev monitor_type 1";
    system "$iwconfig $dev essid $ssid";
    system "$iwconfig $dev rts off";
    system "$iwconfig $dev retries 16";
    # make sure we broadcast at a fixed power
    system "/home/roofnet/bin/prism2_param $dev alc 0";
    system "$iwconfig $dev txpower 23";

}

if ($dev =~ /ath/) {
    system "/sbin/ifconfig ath0 txqueuelen 5";
    if ($mode =~ /a/) {
	system "/sbin/iwpriv ath0 mode 1 1>&2";
    } elsif ($mode=~ /g/) {
	system "/sbin/iwpriv ath0 mode 3 1>&2";
    } else {
	# default b mode
	print STDERR "in b mode\n";
	system "/sbin/iwpriv ath0 mode 2 1>&2";
    }
}


my $probes = "2 60 2 1500 4 1500 11 1500 22 1500";

if ($mode =~ /g/) {
    $probes = "2 60 12 60 2 1500 4 1500 11 1500 22 1500 12 1500 18 1500 24 1500 36 1500 48 1500 72 1500 96 1500";
} elsif ($mode =~ /a/) {
    $probes = "12 60 2 60 12 1500 24 1500 48 1500 72 1500 96 1500 108 1500";
}


my $srcr_es_ethtype = "0941";
my $srcr_forwarder_ethtype = "0943";
my $srcr_ethtype = "0944";
my $srcr_gw_ethtype = "092c";

if ($mode =~ /g/) {
    print "rates :: AvailableRates(DEFAULT 2 4 11 12 18 22 24 36 48 72 96 108,
$wireless_mac 2 4 11 12 18 22 24 36 48 72 96 108);\n\n";
} elsif ($mode =~ /a/) {
    print "rates :: AvailableRates(DEFAULT 12 18 24 36 48 72 96 108,
$wireless_mac 12 18 24 36 48 72 96 108);\n\n";
} else {
    print "rates :: AvailableRates(DEFAULT 2 4 11 22);\n\n";
}

print <<EOF;
// has one input and one output
// takes and spits out ip packets
elementclass LinuxIPHost {
    \$dev, \$ip, \$nm |

  input -> CheckIPHeader()
    -> EtherEncap(0x0800, 1:1:1:1:1:1, 2:2:2:2:2:2) 
    -> SetPacketType(HOST) 
    -> to_host :: ToHost(\$dev);


  from_host :: FromHost(\$dev, \$ip/\$nm) 
    -> fromhost_cl :: Classifier(12/0806, 12/0800);


  // arp packets
  fromhost_cl[0] 
    -> ARPResponder(0.0.0.0/0 1:1:1:1:1:1) 
    -> SetPacketType(HOST) 
    -> ToHost();
  
  // IP packets
  fromhost_cl[1]
    -> Strip(14)
    -> CheckIPHeader 
    -> GetIPAddress(16) 
    -> MarkIPHeader(0)
    -> output;

}




elementclass SniffDevice {
    \$device, \$promisc|
  from_dev :: FromDevice(\$device, PROMISC \$promisc)
  -> t1 :: Tee
  -> output;

    t1 [1] -> ToHostSniffers(\$device);

  input
  -> t2 :: PullTee
  -> to_dev :: ToDevice(\$device);

    t2 [1] -> ToHostSniffers(\$device);
}

sniff_dev :: SniffDevice($dev, false);

sched :: PrioSched()
-> prism2_encap :: Prism2Encap()
-> set_power :: SetTXPower(POWER 63)
//-> Print ("to_dev", TIMESTAMP true)
-> sniff_dev;

route_q :: NotifierQueue(50) 
-> [0] sched;

data_q :: NotifierQueue(50)
-> auto_rate :: MadwifiRate(OFFSET 4,
			    RT rates)
//-> auto_rate :: AutoRateFallback(OFFSET 0,
//				 STEPUP 25,
//				 RT rates)
//-> WifiEncap(0x00, 00:00:00:00:00:00)
//-> Print ("after_rate", TIMESTAMP true)
-> [1] sched;

Idle -> [1] auto_rate;

rate_q :: NotifierQueue(50)
-> static_rate :: SetTXRate(RATE 2)
-> madwifi_rate :: MadwifiRate(OFFSET 4,
			       ALT_RATE false,
			       RT rates,
			       ACTIVE false)
-> arf_rate :: AutoRateFallback(OFFSET 4,
				STEPUP 25,
				ALT_RATE false,
				RT rates,
				ACTIVE false)
-> probe_rate :: ProbeTXRate(OFFSET 4,
			     WINDOW 5000,
			     ALT_RATE false,
			     RT rates,
			     ACTIVE false)

-> [2] sched;

Idle -> [1] probe_rate;
Idle -> [1] madwifi_rate;
Idle -> [1] arf_rate;

// make sure this is listed first so it gets tap0
srcr_host :: LinuxIPHost(srcr, $srcr_ip, $srcr_nm);

srcr_arp :: ARPTable();
srcr_lt :: LinkTable(IP $srcr_ip);


srcr_gw :: GatewaySelector(ETHTYPE 0x$srcr_gw_ethtype,
			   IP $srcr_ip,
			   ETH $wireless_mac,
			   LT srcr_lt,
			   ARP srcr_arp,
			   PERIOD 15,
			   GW $gateway);


srcr_gw 
-> SetSRChecksum 
-> WifiEncap(0x00, 00:00:00:00:00:00)
-> route_q;

srcr_set_gw :: SetGateway(SEL srcr_gw);


srcr_es :: ETTStat(ETHTYPE 0x$srcr_es_ethtype, 
		   ETH $wireless_mac, 
		   IP $srcr_ip, 
		   PERIOD 30000, 
		   TAU 300000, 
		   ARP srcr_arp,
		   PROBES \"$probes\",
		   ETT srcr_ett,
		   RT rates);


srcr_ett :: ETTMetric(ETT srcr_es,
		      LT srcr_lt);


srcr_forwarder :: SRForwarder(ETHTYPE 0x$srcr_forwarder_ethtype, 
			      IP $srcr_ip, 
			      ETH $wireless_mac, 
			      ARP srcr_arp, 
			      LT srcr_lt);


srcr_querier :: SRQuerier(ETHTYPE 0x$srcr_ethtype, 
			  IP $srcr_ip, 
			  ETH $wireless_mac, 
			  LT srcr_lt, 
			  SR srcr_forwarder,
			  ROUTE_DAMPENING true,
			  TIME_BEFORE_SWITCH 5,
			  DEBUG true);

srcr_query_forwarder :: SRQueryForwarder(ETHTYPE 0x$srcr_ethtype, 
					 IP $srcr_ip, 
					 ETH $wireless_mac, 
					 LT srcr_lt, 
					 ARP srcr_arp,
					 DEBUG true);

srcr_query_responder :: SRQueryResponder(ETHTYPE 0x$srcr_ethtype, 
					 IP $srcr_ip, 
					 ETH $wireless_mac, 
					 LT srcr_lt, 
					 ARP srcr_arp,
					 DEBUG true);


srcr_query_responder 
-> SetSRChecksum 
-> WifiEncap(0x00, 00:00:00:00:00:00)
-> route_q;
srcr_query_forwarder 
-> SetSRChecksum 
-> WifiEncap(0x00, 00:00:00:00:00:00)
-> route_q;

srcr_data_ck :: SetSRChecksum() 

srcr_host 
-> SetTimestamp()
-> counter_incoming :: IPAddressCounter(USE_DST true)
-> srcr_host_cl :: IPClassifier(dst net $srcr_ip mask $srcr_nm,
				-)
-> srcr_querier
-> srcr_data_ck;


srcr_host_cl [1] -> [0] srcr_set_gw [0] -> srcr_querier;

srcr_forwarder[0] 
  -> srcr_dt ::DecIPTTL
  -> srcr_data_ck
  -> WifiEncap(0x00, 00:00:00:00:00:00)
  -> data_q;
srcr_dt[1] -> ICMPError($srcr_ip, timeexceeded, 0) -> srcr_querier;


// queries
srcr_querier [1] 
-> SetSRChecksum 
-> WifiEncap(0x00, 00:00:00:00:00:00)
-> route_q;

srcr_es 
-> SetTimestamp()
-> WifiEncap(0x00, 00:00:00:00:00:00)
-> route_q;

srcr_forwarder[1] //ip packets to me
  -> StripSRHeader()
  -> CheckIPHeader()
  -> from_gw_cl :: IPClassifier(src net $srcr_net mask $srcr_nm,
				-)
  -> counter_outgoing :: IPAddressCounter(USE_SRC true)
  -> srcr_host;

from_gw_cl [1] -> [1] srcr_set_gw [1] -> srcr_host;


EOF

    if ($txf) {
print <<EOF;
txf :: WifiTXFeedback() 
-> prism2_decap_txf :: Prism2Decap()
-> rate_cl :: Classifier(30/0100, 
			 -);

FromHost(rate-txf, 1.1.1.1/32) -> Discard;

rate_cl 
-> txf_t :: Tee(4)
-> PushAnno() 
-> ToHost(rate-txf);

rate_cl [1] -> [1] auto_rate;

txf_t [1] -> [1] arf_rate;
txf_t [2] -> [1] madwifi_rate;
txf_t [3] -> [1] probe_rate;


sniff_dev 
-> SetTimestamp() 
-> prism2_decap :: Prism2Decap()
-> dupe :: WifiDupeFilter(WINDOW 5) 
-> wifi_cl :: Classifier(0/00%0c, //mgt
			 0/04%0c, //ctl
			 0/08%0c, //data
			 -);



EOF
}

    if ($ap) {
	print <<EOF;

beacon_source :: BeaconSource(INTERVAL $interval,
                              CHANNEL $channel,
                              SSID "$ssid",
                              BSSID $wireless_mac,
                              RT rates,
                              );


ar :: AssociationResponder(DEBUG true,
                           INTERVAL $interval,
                           SSID "$ssid",
                           BSSID $wireless_mac,
                           RT rates,);



auth_resp :: OpenAuthResponder(DEBUG true,
                          BSSID $wireless_mac);

auth_req :: OpenAuthRequester(ETH $wireless_mac);
assoc_req ::  AssociationRequester(ETH $wireless_mac,
			       RT rates);

auth_req -> route_q;
assoc_req -> route_q;

beacon_source -> route_q;
auth_resp -> route_q;
ar -> route_q;


wifi_cl [0] 
-> management_cl :: Classifier(0/00%f0, //assoc req
			       0/10%f0, //assoc resp
			       0/40%f0, //probe req
			       0/50%f0, //probe resp
			       0/80%f0, //beacon
			       0/a0%f0, //disassoc
			       0/b0%f0, //auth
			       );



management_cl [0] -> Print ("assoc_req") -> ar;
management_cl [1] -> Print ("assoc_resp") -> assoc_req;
management_cl [2] -> beacon_source;
management_cl [3] -> Print ("probe_resp", 200) -> bs :: BeaconScanner(RT rates) -> Discard;
management_cl [4] -> bs;
management_cl [5] -> Print ("disassoc") -> Discard;
management_cl [6] -> Print ("auth") -> auth_t :: Tee(2) -> auth_resp;

auth_t [1] -> auth_req;

probe :: ProbeRequester(ETH $wireless_mac,
			SSID "",
			RT rates)
-> PrintWifi(probe-req) 
-> Print(probe-req) 
-> route_q;


EOF
} else {
print <<EOF;
    wifi_cl[0] -> Discard;
EOF
}

print <<EOF;
wifi_cl [1] -> Discard;
wifi_cl [3] -> Discard;


wifi_cl [2]
-> ap_cl :: Classifier(1/01%03, // TODS packets
		       -);

ap_cl [0]
EOF

    if ($ap) {
	print <<EOF;
-> WifiDecap() 
-> SetPacketType(HOST)
-> CheckIPHeader(OFFSET 16)
-> ToHost(ap);

ap_host :: FromHost(ap, $ap_ip/$srcr_nm, ETHER $wireless_mac) 
-> ap_encap :: WifiEncap(0x02, $wireless_mac)
-> data_q;
EOF
} else {
    print <<EOF;
->Discard;
EOF
}

print <<EOF;
FromHost(station, 1.1.1.2/32, ETHER $wireless_mac)
-> station_encap :: WifiEncap(0x01, $wireless_mac)
-> data_q;



ap_cl [1] 
-> WifiDecap()
-> HostEtherFilter($wireless_mac, DROP_OTHER true, DROP_OWN true) 
//-> rxstats :: RXStats()
-> ncl :: Classifier(
		     12/$srcr_forwarder_ethtype, //srcr_forwarder
		     12/$srcr_ethtype, //srcr
		     12/$srcr_es_ethtype, //srcr_es
		     12/$srcr_gw_ethtype, //srcr_gw
		     12/0106,
		     12/0100,
		     -);


// ethernet packets
ncl[0] -> CheckSRHeader() -> [0] srcr_forwarder;
ncl[1] -> CheckSRHeader() -> PrintSR(srcr) -> srcr_query_t :: Tee(2);

srcr_query_t [0] -> srcr_query_forwarder;
srcr_query_t [1] -> srcr_query_responder;

ncl[2] -> srcr_es;
ncl[3] -> CheckSRHeader() -> srcr_gw;

ncl[4] -> StoreData(12,\\<0806>) -> ToHost(rate);
ncl[5] -> StoreData(12,\\<0800>) -> ToHost(rate);
ncl[6] -> ToHost(safe);

FromHost(safe, $safe_ip/8, ETHER $wireless_mac) 
-> WifiEncap(0x0, 00:00:00:00:00:00)
-> SetTXRate(RATE 2)
-> route_q;

FromHost(rate, $rate_ip/8, ETHER $wireless_mac) 
-> arp_cl :: Classifier(12/0806,
			12/0800);
arp_cl [0] 
-> StoreData(12, \\<0106>)
-> WifiEncap(0x0, 00:00:00:00:00:00)
-> SetTXRate(RATE 2)
-> route_q;

arp_cl [1] 
-> StoreData(12, \\<0100>)
-> SetTXRate(RATE 2)
-> WifiEncap(0x0, 00:00:00:00:00:00)
-> rate_q;

EOF
