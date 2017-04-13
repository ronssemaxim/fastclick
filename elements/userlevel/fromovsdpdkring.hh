#ifndef CLICK_FROMOVSDPDKRING_USERLEVEL_HH
#define CLICK_FROMOVSDPDKRING_USERLEVEL_HH

#include <click/task.hh>
#include <click/notifier.hh>
#include <click/batchelement.hh>
#include <click/dpdkdevice.hh>

CLICK_DECLS

/*
=title FromOVSDPDKRing

=c

FromOVSDPDKRing(MEMPOOL [, I<keywords> BURST, NDESC])

=s netdevices

reads packets from a circular ring buffer using DPDK (user-level)

=d

Reads packets from the ring buffer with name MEMPOOL.
On the contrary to FromDevice.u which acts as a sniffer by default, packets
received by devices put in DPDK mode will NOT be received by the kernel, and
will thus be processed only once.

Arguments:

=over 8

=item MEMPOOL

String. The name of the memory pool to attach. Must be the same as the one used by OVS.
To get the name: 'grep -a ovs /var/run/.<file_prefix>_config ', where file_prefix is the name
of the DPDK EAL prefix passed to OVS (using --dpdk --file-prefix)

=item RING_NAME

String. The name of the ring's queue. Eg: 'dprkr0_tx'. Execute 'ovs-ofctl show br0' 
to get a list of dpdk ports on the OVS switch with name "br0". The ring must 
exist before starting the click script.. The ring must exist before starting the click script

=item BURST

Integer. Maximum number of packets that will be processed before rescheduling.
The default is 32.

=item NDESC

Integer. Number of descriptors per ring. The default is 1024.

=item NUMA_ZONE

Integer. The NUMA memory zone (or CPU socket ID) where we allocate resources.

=back

This element is only available at user level, when compiled with DPDK support.

=e
  DPDKInfo(NB_MBUF 1048576, MBUF_SIZE 4096, MBUF_CACHE_SIZE 512, MEMPOOL_PREFIX ovs_mp_1500_0_);

  FromOVSDPDKRing(MEM_POOL 262144, RING_NAME dpdkr0_tx, BURST 32)
    -> Print("AtRing0, tx")
    -> ToDPDKRing(MEM_POOL 262144, RING_NAME dpdkr0_rx, BURST 32);

=h pkt_count read-only

Returns the number of packets read from the ring.

=h byte_count read-only

Returns the number of bytes read from the ring.

=a DPDKInfo, ToDPDKRing */

class FromOVSDPDKRing : public BatchElement {

    public:
        FromOVSDPDKRing () CLICK_COLD;
        ~FromOVSDPDKRing() CLICK_COLD;

        const char    *class_name() const { return "FromOVSDPDKRing"; }
        const char    *port_count() const { return PORTS_0_1; }
        const char    *processing() const { return PUSH; }
        int       configure_phase() const { return CONFIGURE_PHASE_PRIVILEGED - 5; }
        bool can_live_reconfigure() const { return false; }

        int  configure   (Vector<String> &, ErrorHandler *) CLICK_COLD;
        int  initialize  (ErrorHandler *)           CLICK_COLD;
        void add_handlers()                 CLICK_COLD;
        void cleanup     (CleanupStage)             CLICK_COLD;

        // Calls either push_packet or push_batch
        bool run_task    (Task *);

    private:
        Task _task;

        struct rte_mempool *_message_pool;
        struct rte_ring    *_recv_ring;

        String _MEM_POOL;
        String _PROC;
        String _ring_name;

        unsigned     _ndesc;
        unsigned     _burst_size;
        unsigned     _def_burst_size;
        unsigned int _iqueue_size;
        short        _numa_zone;

        counter_t    _pkts_recv;
        counter_t    _bytes_recv;

        static String read_handler(Element*, void*) CLICK_COLD;
};

CLICK_ENDDECLS

#endif // CLICK_FROMOVSDPDKRING_USERLEVEL_HH
