for dir in */; do
    if [ -d "$dir" ]; then
        echo "Building in $dir..."
        (cd "$dir" && \
        sudo pkgmk -d && \
        sudo pkgmk -uf && \
	sudo pkgmk -us && \
	sudo pkgmk -um && \
        sudo rm -f *.tar.* stable)
    fi
done

# Generate the ports page
httpup-repgen .
./portsmark.sh . > README.md

# Remove unwanted lines from REPO file
if [ -f "REPO" ]; then
    sed -i '/\.git\|/\.sh\|index\.html/d' REPO
    echo "Removed lines containing .git, updateports.sh, and index.html from REPO"
fi
git add . 
git commit -m " New Packages "
git push
