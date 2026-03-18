# Μέρος 1ο: Εκμετάλλευση του Buffer Overflow στο iwconfig

## 1. Source Code Analysis
Αναλύοντας τον πηγαίο κώδικα του `iwconfig`, εντοπίστηκε μια κρίσιμη ευπάθεια Buffer Overflow στη συνάρτηση `get_info()`. Συγκεκριμένα, η συνάρτηση χρησιμοποιεί την επισφαλή κλήση `strcpy`:

```c
struct ifreq ifr;
strcpy(ir.ifr_name, ifname);
```

Η `strcpy` αντιγράφει το input του χρήστη ifname, στη δομή `ifr.ifr_name`, η οποία έχει σταθερό και περιορισμένο μέγεθος, χωρίς να ελέγχει το μήκος των δεδομένων. Aυτό επιτρέπει στον επιτιθέμενο να εισάγει δεδομένα μεγαλύτερα πό το μέγεθος του buffer, υπερχειλίζοντας τη στοίβα και αντικαθιστώντας τα δεδομένα κρίσιμων καταχωρητών, όπως τον EIP.


## 2. Εύρεση του Offset και έλεγχος του EIP
Για να ελέγξουμε τη ροή εκτέλεσης του προγράμματος, έπρεπε να βρούμε το offset μεταξύ της αρχής του buffer και του EIP. Μέσω του GDB και περνώντας διαφορετικά strings, υπολογίσαμε ότι η απόσταση (offset) μέχρι τον EIP είναι ακριβώς 76 bytes. Ξεπερνώντας αυτό το όριο, προκαλούμε Segmentation Fault και τα επόμενα 4 bytes γράφονται απευθείας στον καταχωρητή EIP. Επιβεβαιώσαμε τον έλεγχο στέλνοντας 76 "Α" και 4 "Β", με αποτέλεσμα ο EIP να γεμίσει με `0x42424242`.


## 3. Stack & Environment Shift
Ελέγχοντας την κατάσταση του συστήματος με την εντολή `cat /proc/sys/kernel/randomize_va_space`, επιβεβαιώσαμε ότι το ASLR είναι απενεργοποιημένο (αφού έδωσε αποτέλεσμα `0`) και άρα η στοίβα παραμένει σταθερή και δεν τυχαιοποιείται. Ωστόσο, κατά την εκτέλεση προέκυψε το φαινόμενο του "Stack Shift". Κατά την εκτέλεση σε Bash, τα Environment Variables και το όνομα κλήσης `argv[0]` αλλάζουν το μέγεθος της στοίβας σε σχέση με τον GDB, μετατοπίζοντας τη διεύθυνση-στόχο. Στον GDB (`env -i`), το NOP Sled μας βρισκόταν στην περιοχή `0xffffd930`-`0xffffd990`. Στο πραγματικό τερματικό Bash, η στοίβα είχε μετατοπιστεί χαμηλότερα.


## 4. Payload Delivery & Εύρεση Πραγματικής Διεύθυνσης
Για να παραδώσουμε το payload μέσω Command Substitution με backticks: iwconfig `cat payload`, κατασκευάσαμε ένα python script το οποίο παράγει τα raw bytes και τα προωθεί στο standard output.
Για να βρούμε την ακριβή τοποθεσία της στοίβας στο νέο περιβάλλον του Bash, εκτελέσαμε μια αυτοματοποιημένη σάρωση της μνήμης (brute-force scanning) μέσω ενός bash loop, μεταβάλλοντας τη διεύθυνση του EIP. Η σάρωση αποκάλυψε ότι η πραγματική (shifted) διεύθυνση τoυ NOP sled στο συγκεκριμένο περιβάλλον είναι η `0xffffd758`.


## 5. Payload structure & Shellcode
Το τελικό payload 209 bytes διαμορφώθηκε ως εξής:
1. Padding: 76 bytes (`"A"*76`) για την προσέγγιση του EIP
2. Target EIP: 4bytes (`0xffffd758`, σε Little Endian `\x58\xd7\xff\xff` )
3. NOP Sled: 96 bytes (`\x90`)
4. Shellcode: 33 bytes. Επιλέχθηκε shellcode το οποίο εκτελεί `setuid(0)` και μηδενίζει τους `ebx` και `edx` πριν καλέσει το τερματικό `/bin/sh`.


## 6. Successful Invocation (Proof of Concept)
Ακολουθεί η επιτυχής εκτέλεση της επίθεσης που οδήγησε σε root shell, ικανοποιώντας τις απαιτήσεις της άσκησης:
```c
C:\Users\julio>docker run --rm --privileged -v "C:\Users\julio\OneDrive\Documents\security\exploit.py":/exploit.py -it ethan42/iwconfig:vulnerable bash
ASLR has been disabled for this system. To re-enable it, run:
echo 2 | sudo tee /proc/sys/kernel/randomize_va_space
user@c59cd60b0aaf:/workdir$ python3 /exploit.py>payload
user@c59cd60b0aaf:/workdir$ iwconfig `cat payload`
# whoami
root
#
```