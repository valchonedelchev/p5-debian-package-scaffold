################################################################################
#
# This is a perl package for creating a debian package mandataroy files:
#
#  debian/control
#  debian/copyright
#  debian/changelog
#  debian/prerm
#  debian/postrm
#  debian/preinst
#  debian/postinst
#  debian/conffiles
#
# Requirements:
#  svn2cl
#  basename
#  dirname
#  svn
#
################################################################################
use strict;
use warnings;

package debian;

use constant DEBUG => 0;

sub new
{
    my $class = shift;
    my $self  = {@_};
    bless $self, $class;

    $self->{control}   = new debian::control(@_);
    $self->{copyright} = new debian::copyright(
        exists $self->{Copyright} ? $self->{Copyright} : undef );
    $self->{changelog} = new debian::changelog();
    $self->{preinst}   = new debian::preinst();
    $self->{postinst}  = new debian::postinst();
    $self->{prerm}     = new debian::prerm();
    $self->{postrm}    = new debian::postrm();
    $self->{conffiles} = new debian::conffiles();

    # clean up
    map { delete $self->{$_} if exists $self->{$_} } debian::paragraphs->list;

    if ( -f 'version' ) {
        print "debian->new(): Found version file and i will use it.\n" if DEBUG;
        $self->control->version_from_file('version');
    }

    if ( -f 'prerm' ) {
        print "debian->new(): Found prerm file and will use it.\n" if DEBUG;
        $self->prerm->from_file('prerm');
    }
    if ( -f 'preinst' ) {
        print "debian->new(): Found preinst file and will use it.\n" if DEBUG;
        $self->preinst->from_file('preinst');
    }
    if ( -f 'postrm' ) {
        print "debian->new(): Found postrm file and will use it.\n" if DEBUG;
        $self->postrm->from_file('postrm');
    }
    if ( -f 'postinst' ) {
        print "debian->new(): Found postinst file and will use it.\n" if DEBUG;
        $self->postinst->from_file('postinst');
    }
    if ( -f 'conffiles' ) {
        print "debian->new(): Found conffiles file and will use it.\n" if DEBUG;
        $self->conffiles->from_file('conffiles');
    }

    return $self;
}

sub control   { shift->{control} }
sub copyright { shift->{copyright} }
sub changelog { shift->{changelog} }
sub prerm     { shift->{prerm}; }
sub preinst   { shift->{preinst} }
sub postinst  { shift->{postinst} }
sub postrm    { shift->{postrm} }
sub filename  { shift->{filename} }
sub conffiles { shift->{conffiles} }

sub pkgdir
{
    my $self = shift;
    return sprintf( "%s_%s_%s",
        $self->control->{Package},
        $self->control->{Version},
        $self->control->{Architecture} );
}

# $debian->build or die "Failed to build debian package!";
sub build
{
    my $self     = shift;
    my $no_clean = shift;

    my $debian_dir = sprintf( "%s/DEBIAN", $self->pkgdir );
    system( "mkdir", "-p", $debian_dir ) unless -d $debian_dir;

    $self->calculate_installed_size;

    $self->control->write( $self->pkgdir );
    $self->copyright->write( $self->pkgdir );
    $self->changelog->write( $self->pkgdir );
    $self->prerm->write( $self->pkgdir );
    $self->postrm->write( $self->pkgdir );
    $self->preinst->write( $self->pkgdir );
    $self->postinst->write( $self->pkgdir );
    $self->conffiles->write( $self->pkgdir );

    system( "fakeroot", "dpkg-deb", "--build", $self->pkgdir );

    my $file = sprintf( "%s.deb", $self->pkgdir );
    $self->{filename} = $file if -f $file and -s $file;

    $self->clean unless $no_clean;
    return $file ? 1 : 0;
}

sub calculate_installed_size
{
    my $self = shift;
    my $dir  = $self->pkgdir;
    chomp( my $size = `du -sbx $dir 2>/dev/null| awk '{print \$1}'` );
    $self->control->{'Installed-Size'} = sprintf( "%d", $size / 1024 );   # ceil
    return $self->control->{'Installed-Size'};
}

sub clean
{
    my $self = shift;
    system( "rm", "-fr", $self->pkgdir ) if length( $self->pkgdir );
}

sub file_put_contents
{
    my $file     = shift;
    my $contents = shift;

    open my $fh, '>', $file or die "Error $file - $!";
    print $fh $contents or die $!;
    close $fh or die $!;
}

# usage:
#  debian->add("../source/to/directory", "/usr/local/");
sub add
{
    my $self   = shift;
    my $source = shift;           # path to source FILE or PATH
    my $dest   = shift || '/';    # absolute path where you want to install it

    warn "Failed to add $source - $!" unless -e $source;
    my $destdir = sprintf( "%s%s", $self->pkgdir, $dest );

    if ( -f $source ) {
        chomp( $a = `basename $source` );
        chomp( $b = `basename $dest` );

        chomp( my $dirname = `dirname $dest` );
        my $dstdirname = sprintf( "%s%s", $self->pkgdir, $dirname );
        system( "mkdir", "-p", $dstdirname ) unless -d $dstdirname;
        system( "cp", $source, $destdir );
    } elsif ( -d $source ) {
        system( "mkdir", "-p", $destdir ) unless -e $destdir;   # create parents
        system("cp --recursive $source/* $destdir/"); # copy recursive all files
    } else {
        die " *** ERROR: Unknown source type: $source\n";
    }
}

# usage:
#  $debian->add_from_svn("../source/lib/php", "/usr/local/lib");
sub add_from_svn
{
    my $self = shift;
    my $src  = shift;           # path to SVN repository
    my $dst  = shift || '/';    # desired installation path

    my $path = sprintf( "%s%s", $self->pkgdir, $dst );
    if ( -f $src ) {
        chomp( my $d = `dirname $path` );
        system( 'mkdir', '-p', $d ) unless -e $d;
    } elsif ( -d $src ) {
        system( 'mkdir', '-p', $path ) unless -e $path;
    }
    system( "svn", "export", "--quiet", "--force", $src, $path );
}

sub get_svn_revision
{
    my $self = shift;
    my $path = shift || '..';

    #qx 'svn up $path';
    chomp( my $revision =
          `svn info $path | grep 'Revision: '| sed 's/Revision: //'` );
    return $revision;
}

sub to_string
{
    my $self = shift;
    eval {
        use Data::Dumper;
        print Dumper $self;
    };
}

sub gcc_version
{
    chomp( my $gcc_version = `gcc --version | grep ^gcc | sed 's/^.* //g'` );
    return $gcc_version;
}

sub get_arch
{
    chomp( my $arch = `dpkg-architecture -qDEB_BUILD_ARCH` );
    return $arch;
}

################################################################################
# debian::changelog
################################################################################
package debian::changelog;

sub new
{
    my $class = shift;
    my $self = { Changelog => shift || '' };
    bless $self, $class;
    return $self;
}

sub from_svn
{
    my $self = shift;
    my $from = shift;

    $from = quotemeta $from;
    $self->{Changelog} =
      `svn2cl --stdout --group-by-day --include-rev $from -a --limit 1`;
    return $self->{Changelog};
}

sub set
{
    my $self  = shift;
    my $value = shift;
    $self->{Changelog} = $value if defined $value;
    return $self->{Changelog};
}

sub to_string
{
    shift->{Changelog};
}

sub file
{
    return 'DEBIAN/changelog';
}

sub write
{
    my $self = shift;
    my $path = shift || '.';
    debian::file_put_contents( $path . '/' . $self->file, $self->to_string );
}

################################################################################
# debian::copyright
################################################################################
package debian::copyright;

sub new
{
    my $class = shift;
    my $self = { Copyright => shift || '' };
    bless $self, $class;
    return $self;
}

sub set
{
    my $self  = shift;
    my $value = shift;
    $self->{Copyright} = $value if defined $value;
    return $self->{Copyright};
}

sub to_string
{
    shift->{Copyright};
}

sub file
{
    return 'DEBIAN/copyright';
}

sub write
{
    my $self = shift;
    my $path = shift || '.';
    debian::file_put_contents( $path . '/' . $self->file, $self->to_string );
}

################################################################################
# debian::control
################################################################################
package debian::control;

sub new
{
    my $class = shift;
    my $self  = {@_};
    bless $self, $class;

    $self->{Architecture} = 'all'      unless defined $self->{Architecture};
    $self->{Section}      = 'web'      unless defined $self->{Section};
    $self->{Priority}     = 'optional' unless defined $self->{Priority};
    $self->{Depends}      = 'binutils' unless defined $self->{Depends};
    $self->{Maintainer} = 'Developers <dev-team@example.com>'
      unless defined $self->{Maintainer};
    $self->{Homepage} = 'http://www.example.com/'
      unless defined $self->{Homepage};
    $self->{Copyright} = 'Example Soft' unless defined $self->{Copyright};
    $self->{Version}   = '0.0'          unless defined $self->{Version};

    return $self;
}

sub to_string
{
    my $self = shift;
    my $control;
    foreach my $key ( debian::paragraphs->list ) {
        next unless exists $self->{$key} and defined $self->{$key};
        $control .= sprintf( "%s: %s\n", $key, $self->{$key} );
    }
    return $control;
}

sub file
{
    return 'DEBIAN/control';
}

sub write
{
    my $self = shift;
    my $path = shift || '.';
    debian::file_put_contents( $path . '/' . $self->file, $self->to_string );
}

# use this method to append SVN revision at the end of versin sting
# a normal version string is: 1.0.1
# as result you'll get: 1.0.1.9893
#
# usage:
# $debian->control->append_to_version( $debian->get_svn_revision );
sub append_to_version
{
    my $self = shift;
    my $str  = shift;
    $self->{Version} .= '.' . $str;
}

sub version_from_file
{
    my $self = shift;
    my $file = shift;
    die "version_from_file() failed: $file - $!\n" unless -f $file;
    if ( not -s $file ) {
        warn "WARNING: Found version file ($file) but empty. Not using it!\n";
        return;
    }
    chomp( $self->{Version} = qx(cat $file) );
}

################################################################################
# debian::paragraphs
################################################################################
package debian::paragraphs;

sub list
{
    return qw(
      Package
      Conflicts
      Source
      Version
      Section
      Priority
      Architecture
      Essential
      Depends
      Installed-Size
      Maintainer
      Homepage
      Description
    );
}

################################################################################
# debian::hook
################################################################################
package debian::hook;
use base 'Class::Accessor::Fast';

#sub new { bless {}, shift }
sub to_string { $_[0]->{Content} }
sub from_string { $_[0]->{Content} = $_[1] }

sub from_file
{
    die "file error: $_[1] - $!" unless -f $_[1];
    $_[0]->{Content} = qx( cat $_[1] );
}
sub file { die "abstract"; }
sub mode { 0755 }

sub write
{
    my $self = shift;
    my $path = shift || '.';
    if ( defined $self->to_string and length $self->to_string ) {
        debian::file_put_contents( $path . '/' . $self->file,
            $self->to_string );
        chmod $self->mode, $path . '/' . $self->file;
    }
}

################################################################################
# debian::prerm
################################################################################
package debian::prerm;
use base 'debian::hook';
sub file { 'DEBIAN/prerm' }

################################################################################
# debian::postrm
################################################################################
package debian::postrm;
use base 'debian::hook';
sub file { 'DEBIAN/postrm' }

################################################################################
# debian::preinst
################################################################################
package debian::preinst;
use base 'debian::hook';
sub file { 'DEBIAN/preinst' }

################################################################################
# debian::postinst
################################################################################
package debian::postinst;
use base 'debian::hook';
sub file { 'DEBIAN/postinst' }

################################################################################
# debian::conffiles
################################################################################
package debian::conffiles;
use base 'debian::hook';
sub file { 'DEBIAN/conffiles' }
sub mode { 0644 }

sub to_string
{
    my ($self) = @_;
    if ( $self->{Content} ) {
        $self->{Content} =~ s/\n+/\n/g;
        $self->{Content} .= "\n" unless $self->{Content} =~ m/\n$/;
    }
    return $self->{Content};
}

sub from_string
{
    my ( $self, $string ) = @_;
    $string =~ s/\n+/\n/g;
    $string .= "\n" unless $string =~ m/\n$/;
    $self->{Content} .= $string;
}

sub from_file
{
    my ( $self, $file ) = @_;
    die "file error: $file - $!" unless -f $file;
    $self->{Content} .= qx( cat $file );
}

1;

__END__

=head1 USAGE

    
    use strict;
    use warnings;
    use debian;
    
    my $debian = new debian(
        Package      => "pretty-cool-software",
        Version      => '1.0.0',
        Description  => 'Pretty cool software with awesome functionality',
        Architecture => 'all',
        Section      => 'perl',
        Priority     => 'optional',
        Depends      => 'perl',
        Maintainer   => 'Developer <me@example.com>',
        Homepage     => 'https://example.tld/project',
        Copyright    => 'GPL'
    );
    
    # Use last entry in subversion as changelog
    $debian->changelog->from_svn("../source/lib/php");
    
    # Suffix svn revision to version sting
    $debian->control->append_to_version( $debian->get_svn_revision );
    
    # Add a regular file
    $debian->add("../source/etc/init.d/serviced.php", '/etc/init.d/serviced.php');
    
    # Add folder from subversion
    $debian->add_from_svn("../source/lib/service/php", "/usr/local/lib/service");
    
    # add prerm, postrm, preinst, postinst sripts to DEBIAN/* path
    $debian->prerm->from_string(&prerm);
    $debian->preinst->from_string(&preinst);
    $debian->postinst->from_string(&postinst);
    $debian->postrm->from_string(&postrm);
    
    # Finaly build a debian package
    $debian->build or die "Failed to build package!\n";

=cut

