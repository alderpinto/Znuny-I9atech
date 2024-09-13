package var::packagesetup::RS4OTRS_API;

use strict;
use warnings;

use Kernel::System::SysConfig;
use Data::Dumper;
use File::Copy qw(copy);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Stats',
    'Kernel::System::SysConfig',
    'Kernel::System::Valid',
);

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    my $IsAdvancedTicketSearchInstalled =
      $Kernel::OM->Get('Kernel::System::API::Util')
      ->IsAdvancedTicketSearchInstalled;

    return 1 if !$IsAdvancedTicketSearchInstalled;

    $Kernel::OM->Get('Kernel::System::Ticket::Event::CheckInstalledPackage')->Run(
        Event  => 'PackageInstall',
        Data   => {
            Name    => 'RS4OTRS_AdvancedTicketSearch',
            Version => '6.1.24'
        },
        Config => {}
    );
    return 1;
}

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    my $IsAdvancedTicketSearchInstalled =
      $Kernel::OM->Get('Kernel::System::API::Util')
      ->IsAdvancedTicketSearchInstalled;

    return 1 if !$IsAdvancedTicketSearchInstalled;

    $Kernel::OM->Get('Kernel::System::Ticket::Event::CheckInstalledPackage')->Run(
        Event  => 'PackageUninstall',
        Data   => {
            Name    => 'RS4OTRS_AdvancedTicketSearch',
            Version => '6.1.24'
        },
        Config => {}
    );
    return 1;
}

sub CodeReinstall {
    my ( $Self, %Param ) = @_;

    my $IsAdvancedTicketSearchInstalled =
      $Kernel::OM->Get('Kernel::System::API::Util')
      ->IsAdvancedTicketSearchInstalled;

    return 1 if !$IsAdvancedTicketSearchInstalled;

    $Kernel::OM->Get('Kernel::System::Ticket::Event::CheckInstalledPackage')->Run(
        Event  => 'PackageReinstall',
        Data   => {
            Name    => 'RS4OTRS_AdvancedTicketSearch',
            Version => '6.1.24'
        },
        Config => {}
    );
    return 1;
}

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    my $IsAdvancedTicketSearchInstalled =
      $Kernel::OM->Get('Kernel::System::API::Util')
      ->IsAdvancedTicketSearchInstalled;

    return 1 if !$IsAdvancedTicketSearchInstalled;

    $Kernel::OM->Get('Kernel::System::Ticket::Event::CheckInstalledPackage')->Run(
        Event  => 'PackageUpgrade',
        Data   => {
            Name    => 'RS4OTRS_AdvancedTicketSearch',
            Version => '6.1.24'
        },
        Config => {}
    );
    return 1;
}

1;
