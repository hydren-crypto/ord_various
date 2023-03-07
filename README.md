

# Inscribe and Send Scripts for [ord](https://github.com/casey/ord) 

These scripts are helpers for the ord wallet located at https://github.com/casey/ord. 

## `inscribe.sh`
Automates processing of ordinal inscriptions. Saves all related output to the inscription to 'inscribe_log.json' including the filename inscribed and user controlled description field.

## `send.sh`
Automates mass sending inscriptions via lookups on the filename or description in the `inscribe_log.json` file. Stores a record of the transaction in the `inscribe_log.json`.

Syntax:
```
./inscribe.sh [options] <filename>
```

Options:

- `-s` Skip prompt to proceed with inscription 
- `-d <description>` Specify a description for the inscription

Example to inscribe all files in a directory called `./pending` using the default fee rate:
```
for filename in ./pending/*; do ./inscribe.sh "$filename"; done
```

Example to inscribe all files in a directory and skip prompts:
```
for filename in ./pending/*; do ./inscribe
```