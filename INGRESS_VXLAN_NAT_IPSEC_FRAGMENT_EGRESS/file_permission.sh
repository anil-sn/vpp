#!/bin/bash

# Define the target directory as the first argument, or use the current directory if not provided.
TARGET_DIR="${1:-.}"

# Check if the target directory exists.
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' not found."
    exit 1
fi

echo "Setting permissions for files and directories in '$TARGET_DIR'..."

# --- Set standard Unix permissions ---

# Use 'find' to set permissions for all directories (type d).
# - 775: Full permissions for owner and group, read/execute for others.
# - The 'g+s' sets the SGID bit, ensuring newly created files inherit the group.
echo "Setting permissions for directories to 775..."
find "$TARGET_DIR" -type d -exec chmod g+s,775 {} +

# Use 'find' to set permissions for all files (type f).
# - 664: Read/write for owner and group, read-only for others.
echo "Setting permissions for files to 664..."
find "$TARGET_DIR" -type f -exec chmod 664 {} +

# --- Enhance directory protection ---

# Add the sticky bit to all directories.
# This prevents users from deleting or renaming files within the directory unless they own the file.
echo "Adding sticky bit to directories to prevent unauthorized deletion..."
find "$TARGET_DIR" -type d -exec chmod +t {} +

echo "Permissions have been set successfully for the NFS project directory.