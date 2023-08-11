#!/bin/bash
calculate_hashes() {
    file_path=$1
    sha256_hash=$(sha256sum "$file_path" | awk '{ print $1 }')
    sha512_hash=$(sha512sum "$file_path" | awk '{ print $1 }')
    echo "$sha256_hash" "$sha512_hash"
}
# Function to compare versions
compare_versions() {
    version1=$1
    version2=$2
    if [[ $version1 == "$version2" ]]; then
        return 0  # Versions are equal
    elif [[ $version1 > $version2 ]]; then
        return 1  # version1 is greater
    else
        return 2  # version2 is greater
    fi
}

# Read JSON file
packs_json="packs.json"  # Adjust the JSON file path as needed
data=$(cat "$packs_json")

# Universal variables
featured=$(echo "$data" | jq -r '.universal_variables.featured')
dependencies=$(echo "$data" | jq -r '.universal_variables.dependencies')
loaders=$(echo "$data" | jq -r '.universal_variables.loaders')
primary=$(echo "$primary" | jq -r 'universal_variables.primary')

# Iterate over packs
for pack in $(echo "$data" | jq -c '.packs[]'); do
    name=$(echo "$pack" | jq -r 'keys[0]')
    pack_data=$(echo "$pack" | jq -r ".$name")
    version=$(echo "$pack_data" | jq -r '.version')
    changelog=$(echo "$pack_data" | jq -r '.changelog')
    minecraft_versions=$(echo "$pack_data" | jq -r '.minecraft_versions')
    type=$(echo "$pack_data" | jq -r '.type')
    modrinth_id=$(echo "$pack_data" | jq -r '.modrinth_id')

     # Create zip file
    zip_filename="${name}_${version}.zip"
    pushd "$name" || exit  # Move into the directory
    zip -r "../$zip_filename" ./*  # Include only the contents of the directory
    popd || exit  # Move back to the original directory

    # Calculate size of the zip file
    zip_size=$(du -b "$zip_filename" | awk '{ print $1 }')
    # Create zip file
    zip -r "$zip_filename" "$name"

    # Calculate hashes for the zip file
    hashes=("$(calculate_hashes "$zip_filename")")
    sha256_hash=${hashes[0]}
    sha512_hash=${hashes[1]}

    # Rest of the deployment logic...

    # Construct the data for the POST request
    post_data=$(jq -n \
            --arg name "$name" \
            --arg version_number "$version" \
            --argjson dependencies "$dependencies" \
            --argjson game_versions "$minecraft_versions" \
            --arg version_type "$type" \
            --argjson changelog "$changelog" \
            --argjson loaders "$loaders" \
            --argjson featured "$featured" \
            --arg url "https://cdn.modrinth.com/data/$modrinth_id/versions/$version/$zip_filename" \
            --arg filename "$zip_filename" \
            --arg primary false \
            --arg size "$zip_size" \
            --arg sha256 "$sha256_hash" \
            --arg sha512 "$sha512_hash" \
            '{name: $name, version_number: $version_number, dependencies: $dependencies, game_versions: $game_versions, version_type: $version_type, changelog: $changelog, loaders: $loaders, featured: $featured, files: [{"hashes": {"sha256": $sha256, "sha512": $sha512}, "url": $url, "filename": $filename, "primary": $primary, "size": ($size | tonumber), "file_type": "required-resource-pack"}]}')

    # Send the POST request using curl
    curl -X POST "https://api.modrinth.com/v2/project/$modrinth_id/version" \
        -H "Authorization: Bearer $MODRINTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$post_data"

    if [ $? -eq 0 ]; then
        echo "Version creation successful for $name $version"
    else
        echo "Version creation failed for $name $version"
    fi
done