# Setting Up GPG for Signing Git Commits on Ubuntu Machines

This guide will walk you through the process of generating a GPG key and configuring Git to use it for signing your commits. Signing your commits provides a way to verify that the commits you push to repositories are truly from you.

## Prerequisites

Ensure that you have GPG installed on your system. Here are the installation steps for Ubuntu operating system:

### Installing GPG

- **UbuntuOS**:
```bash
  sudo apt-get install gnupg
```

### Step 1: Generate a New GPG Key

To generate a new GPG key, open your terminal and run:
```bash
gpg --full-generate-key
```
- You will be prompted to provide some information:

    - **Select Key Type**: Choose RSA and RSA (default).
    - **Key Size**: Choose 4096 bits for stronger security.
    - **Key Expiration**: Choose a key expiration date. You can set it to never expire or choose an expiration date based on your preference.
    - **User ID**: Enter your name and email address (use the email associated with your GitHub account).
    - **Passphrase**: Choose a strong passphrase to protect your key.

After completing these steps, GPG will generate your key.

### Step 2: List Your GPG Keys

To list your GPG keys and find your newly created key's ID, use:
```bash
gpg --list-secret-keys --keyid-format LONG
```

The output will look like this:
```bash
/home/user/.gnupg/secring.gpg
------------------------------
sec   4096R/1234ABCD 2024-08-10 [expires: 2026-08-10]
uid                          Your Name <your.email@example.com>
ssb   4096R/5678EFGH 2024-08-10
```

- The key ID is the part after **4096R/** and before the date, in this example, **1234ABCD**.

### Step 3: Configure Git to Use Your GPG Key

Now that you have your GPG key ID, you need to configure Git to use it for signing commits.

## 3.1 Set the GPG Key for Git

Run the following command to set your GPG key in Git:
```bash
git config --global user.signingkey 1234ABCD
```
Replace 1234ABCD with your actual GPG key ID.

## 3.2 Enable Automatic Commit Signing

To ensure that all your commits are signed by default, enable commit signing globally:
```bash
git config --global commit.gpgSign true
```

### Step 4: Export and Add Your GPG Key to GitHub

For GitHub to recognize your signed commits, you need to add your public GPG key to your GitHub account.
## 4.1 Export Your Public GPG Key

Export your public key using the following command:
```bash
gpg --armor --export 1234ABCD > gpg-key.asc
```
This will create a file named gpg-key.asc containing your public key.
## 4.2 Add the GPG Key to GitHub

   - Open the gpg-key.asc file in a text editor and copy the entire contents.
   - Go to GitHub GPG Keys Settings.
   - Click New GPG key.
   - Paste your public key into the text box and click Add GPG key.

That should effective help you sign your commits on github