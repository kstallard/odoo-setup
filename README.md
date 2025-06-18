MIT License

Copyright (c) 2025 Kevin Stallard

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Introduction

These files are to instantiate a new odoo server.

This assumes Cent OS 10 (CentOS Stream release 10 (Coughlan)).  But you can use AlmaLinux as well.  Come to think if it, anything RedHat might work.  But this has been exensively tested on Cent OS 10. If using something else, you miliage may vary.

## Pre-Install Instructions
After you install the OS of choice (keep in mind this uses `dnf` (rpm packages, Fedora) insted of `apt` (deb packages, Debian) ), and you get networking configured properly, you'll need to also install core development tools (gcc, ld, make, etc)

`sudo dnf update`
`sudo dnf grupinstall "Development Tools"`

You'll also need 'git'

`sudo dnf install git`

## If you have ssh keys for git hub, update them
- `mkdir .ssh`
- `chmod 700 .ssh`
- `vim .ssh/odoo_enterprise`
- `vim .ssh/odoo_enterprise.pub`
- `chmod 600 .ssh/odoo_enterprise`
- `chmod 644 .ssh/odoo_enterprise.pub`

-- Note: If you don't have ssh keys, the setup script will create them and provide you with an opportunity to update your github account with the new key

## TLS/SSL
You also need to have a public key, certificate chain of trust and a private key for ssl in the same directory as this script.  The script will copy it to a subfoler `/etc/letsencrypt`.  If you want to change that location, you'll need to update the script, make sure you find all of the directory locations (one is in the config file as well).

The public key plus the certificate chain of trust needs to be named `fullchain.pem`, and the private key file needs to be named `privkey.pem`.

I have only tested this on my system, again, there may be small variances that you'll need to accomodate for in whatever context this is run.
 
## Install Odoo

Before running the script, you'll need to edit it.  Search for `;admin_password`

You'll need to select a password that you will use when first accessing Odoo and either creating or importing a new database.  Uncomment that line (remove the `;` semi-colon`) as well.  Save the script

One final note before you run this.  There isn't a lot of error detection in the script.  So if something fails, there is the likelihood that it will continue to run.  In most cases, after you correct the issue, you can just rerun the script.  In the unlikly case this won't work, before you run the script, take a snapshot of your VM (if not using Docker) before you run it so you can pick up where you left off.

### Run the installer
`sudo setup-odoo.bash`

Once the install starts, it will display some basic information including the public key you need to associate with your github account. It will then pause and wait for a key press.  This is assuming you've associated your git hub account with Odoo Enterprise repositoy.  If you haven't done so you'll need to do this first or remove Odoo Enterprise related operations from this script.

## Post Install Instructions
A few things need to be done after the install completes

### Load the database
Load you newly installed instance into your browser by going to the ip address you just setup.
https://myodoo-staging.mycompany.com (or the physical ip address)

Make sure the Master password matches what is in /etc/odoo.conf

Upload/Import the database.

### Sync the hash algorithm for passwords
If you are migrating from Odoo online, the hash algorithm for passwords is different.  You'll need to change your admin password directly in the Postgresql database.

After you log into the Odoo server (ssh), do the following:

`sudo bash`  
(enter your password)

`sudo - odoo`  
`cd`  
`cd odoo-server`  
`source ./odoo_venv/bin/activate`  

`python`  
`>>> from passlib.hash import pbkdf2_sha512`  
`>>> password = "<mynewpassword>"`  
`>>> hash = pbkdf2_sha512.hash(password)`  
`>>> print(hash)`  

<prints the hash for the password you assigned to the variable `password`>


`ctl-d` (exit python)

`exit`  (takes you back to the root bash instance)

su - postgres 
psql 

select id, login, password from res_users;

(this will list all of the users)

`update res_users set password = '<copy/past the hash value here>' where login='<the username you want to update>';`

(change the string for login to the user you want to upate, copy and past the hash to the string being set for password.  Don't forget the semi colin at the end)


You should now be able to loginto your newly migrated database.  For the other users, they will need to request a password reset.  Make sure you have your odoo on-premise instance integrated with incomming and outgoing mail servers so that password reset instructions can be delivered to your users.


Please feel free to submit suggestions or improvements.  I hope this helps you along in getting out of the cloud.

