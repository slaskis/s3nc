```
 @@@@@@   @@@@@@   @@@  @@@   @@@@@@@
@@@@@@@   @@@@@@@  @@@@ @@@  @@@@@@@@
!@@           @@@  @@!@!@@@  !@@
!@!           @!@  !@!!@!@!  !@!
!!@@!!    @!@!!@   @!@ !!@!  !@!
 !!@!!!   !!@!@!   !@!  !!!  !!!
     !:!      !!:  !!:  !!!  :!!
    !:!       :!:  :!:  !:!  :!:
:::: ::   :: ::::   ::   ::   ::: :::
:: : :     : : :   ::    :    :: :: :

Command line tool to synchronize two buckets by copying all modified objects
from one bucket to another in parallel for blazing speed (or around 300
objects/s on my machine using 100 threads).

Usage: s3nc.rb [options] SRC DST
    -n, --threads NUMBER             Use NUMBER of threads to copy (default 20)
    -p, --prefix PREFIX              Copy objects prefixed with PREFIX (default "")
    -a, --act ACL                    Copy objects with ACL [private,public-read,public-read-write,authenticated-read,bucket-owner-read,bucket-owner-full-control] (default public-read)
    -k, --key KEY                    Set Amazon Access KEY (default ENV['S3_KEY'])
    -s, --secret SECRET              Sets the Amazon Access SECRET (default ENV['S3_SECRET'])
    -u, --unsafe                     Use http (fast) instead of https (secure)
    -r, --reduced                    Use reduced redundancy storage (cheap) instead of standard (reliable)
    -c, --create                     Create the destination bucket if it does not already exist
    -y, --yes                        Don't ask to continue (useful for cron-jobs)
    -q, --quieter                    Not interested in the progress

## Examples

    $ s3nc myfrombucket mytobucket
    $ s3nc -n 100 myfrombucket mytobucket
    $ s3nc -n 100 -p /to-copy myfrombucket mytobucket

## Dependencies

* https://github.com/appoxy/aws
* https://github.com/grosser/parallel

    $ gem install aws parallel
    
```
