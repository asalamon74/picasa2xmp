**DO NOT USE IT YET, STILL WORKING ON IT**

# picasa2xmp

Converts Picasa face information to XMP tags

```
Usage:
    picasa2xmp.pl [options] --contacts-xml picasa_contacts.xml DIRECTORY

Options:
    DIRECTORY
            Specifies the directory which contains the image files. If not specified the script works on the current directory.

    -x|--exclude-dir
            Specifies the directories (using regular expression) which should be excluded. Default value: "\.picasaoriginals$".

    -c|--contacts-xml
            Specifies the picasa contacts xml file. This is a mandatory option.

    -v|--verbose
            Turns on verbose mode, the program prints out more information. Can be specified multiple times to increase verbosity.

    -n|--dry-run
            Perform a trial run with no changes. Useful for testing.

    -k|--keep-time
            Keep the original dates of the files.

    -h|--help
            Prints out the help page.

    -m|--man
            Prints out the man page.
```
