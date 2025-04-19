echo "============================================"
echo "Starting Install VS Code Extensions"
echo "============================================"

EXTENSIONS=(
    "ms-vscode.cpptools"
    "ms-python.python"
    "redhat.java"
)

for ext in "${EXTENSIONS[@]}"; do
    echo "→ Installing extension: $ext for participant"
    sudo -u participant code --install-extension "$ext" --force
    if [ $? -eq 0 ]; then
        echo "✅ Installed $ext successfully."
    else
        echo "❌ Failed to install $ext." >&2
        exit 1
    fi
done

