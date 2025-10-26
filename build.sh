#!/bin/bash
# build.sh - Build luci-app-usbip-server IPK package
# Compatible with ash and bash environments, can run on Linux/OpenWRT or Windows with Git Bash/Cygwin/MSYS2

# Exit on error
set -e

echo "Building luci-app-usbip-server IPK package..."

# 定义变量 - 确保路径格式兼容Windows和Linux
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
IPKG_DIR="${SCRIPT_DIR}/ipkg"
TMP_DIR="${SCRIPT_DIR}/tmp_build"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PO_DIR="${SCRIPT_DIR}/po/zh_Hans"
PO_FILE="${PO_DIR}/usbip_server.po"
LMO_DIR="${TMP_DIR}/usr/lib/lua/luci/i18n"
LMO_FILE="${LMO_DIR}/usbip_server.lmo"

# 定义包信息
PACKAGE_NAME="luci-app-usbip-server"
PACKAGE_VERSION="1.0.1-1"
ARCHITECTURE="all"
PKG_SUFFIX="xretia_dsai"
IPK_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${PKG_SUFFIX}.ipk"

# Create necessary directories
echo "Creating temporary directories..."
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${LMO_DIR}"

# Create essential directories only
mkdir -p "${TMP_DIR}/etc/config"
mkdir -p "${TMP_DIR}/etc/init.d"
mkdir -p "${TMP_DIR}/etc/uci-defaults"
mkdir -p "${TMP_DIR}/usr/bin"

# Copy files to temporary directory
echo "Copying files to temporary directory..."
# Copy CONTROL directory
mkdir -p "${TMP_DIR}/CONTROL"
cp "${IPKG_DIR}/CONTROL/"* "${TMP_DIR}/CONTROL/" 2>/dev/null || echo "Note: CONTROL directory copy may be incomplete"

# Copy configuration files - from files directory
cp -r "${SCRIPT_DIR}/files/etc/"* "${TMP_DIR}/etc/" 2>/dev/null || echo "Note: etc directory copy from files may be incomplete"

# Copy usr files - from files directory
cp -r "${SCRIPT_DIR}/files/usr/"* "${TMP_DIR}/usr/" 2>/dev/null || echo "Note: usr directory copy from files may be incomplete"

# Copy view files to correct LuCI location
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/view/usbip_server"
cp -r "${SCRIPT_DIR}/files/www/luci-static/resources/view/usbip_server/"* "${TMP_DIR}/usr/lib/lua/luci/view/usbip_server/" 2>/dev/null || echo "Note: view files copy may be incomplete"

# Ensure all directories are created
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/i18n"
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/controller"
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/model/cbi"

# Check if po2lmo command is available
echo "Checking for po2lmo tool..."
if command -v po2lmo &> /dev/null; then
    # Generate lmo file
echo "Generating LMO file from PO file..."
if [ -f "${PO_FILE}" ]; then
    po2lmo "${PO_FILE}" "${LMO_FILE}"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to generate LMO file."
        exit 1
    fi
    echo "LMO file generated successfully: ${LMO_FILE}"
else
    echo "Warning: PO file not found ${PO_FILE}"
fi
else
    echo "Warning: po2lmo command not found. Trying to copy existing lmo file..."
    if [ -f "${IPKG_DIR}/usr/lib/lua/luci/i18n/usbip_server.lmo" ]; then
        cp "${IPKG_DIR}/usr/lib/lua/luci/i18n/usbip_server.lmo" "${LMO_FILE}"
        echo "Copied existing LMO file."
    else
        echo "Warning: Cannot generate or find LMO file. IPK package will not contain localization files."
    fi
fi

# Set file permissions
echo "Setting file permissions..."
# Set default permissions 0644 for all files
find "${TMP_DIR}" -type f -exec chmod 644 {} \;

# Set permissions 0755 for shell scripts and executable files
find "${TMP_DIR}" -name "*.sh" -exec chmod 755 {} \;
find "${TMP_DIR}" -name "usbip_monitor" -exec chmod 755 {} \;
find "${TMP_DIR}" -name "luci-usbip_server" -exec chmod 755 {} \;

# Set executable permissions for CONTROL scripts (prerm and postinst)
chmod 755 "${TMP_DIR}/CONTROL/prerm" "${TMP_DIR}/CONTROL/postinst" 2>/dev/null || true

# Set correct permissions for other CONTROL files
chmod 644 "${TMP_DIR}/CONTROL/control" "${TMP_DIR}/CONTROL/description" 2>/dev/null || true

# Update version and architecture in control file
echo "Updating control file..."
CONTROL_FILE="${TMP_DIR}/CONTROL/control"

# Use Windows-compatible sed syntax
if command -v gsed &> /dev/null; then
    SED_CMD="gsed"
elif command -v sed &> /dev/null; then
    # Check if it's GNU sed (Linux) or BSD sed (macOS)
    if echo "test" | sed -e 's/test/replace/' -i '' 2>/dev/null; then
        # BSD sed (requires empty string parameter)
        SED_CMD="sed -i ''"
    else
        # GNU sed
        SED_CMD="sed -i"
    fi
else
    echo "Error: sed command not found."
    exit 1
fi

# 执行sed命令
$SED_CMD "s/Version: .*/Version: ${PACKAGE_VERSION}/g" "${CONTROL_FILE}"
$SED_CMD "s/Architecture: .*/Architecture: ${ARCHITECTURE}/g" "${CONTROL_FILE}"

# Create temporary directory for packaging
BUILD_TMP="${TMP_DIR}/.build_tmp"
mkdir -p "${BUILD_TMP}"
echo "CONTROL" > "${BUILD_TMP}/tarX"

# Set timestamp
TIMESTAMP=$(date)

# Detect available tar command
echo "Detecting tar command..."
if command -v gtar &> /dev/null; then
    TAR_CMD="gtar"
elif command -v tar &> /dev/null; then
    TAR_CMD="tar"
else
    echo "Error: tar command not found."
    exit 1
fi

# Create data.tar.gz
echo "Creating data.tar.gz..."
$TAR_CMD -X "${BUILD_TMP}/tarX" -czf "${BUILD_TMP}/data.tar.gz" -C "${TMP_DIR}" --owner 0 --group 0 --sort=name .
if [ $? -ne 0 ]; then
    echo "Error: Failed to create data.tar.gz."
    exit 1
fi

# Calculate and update Installed-Size
echo "Updating Installed-Size..."
if command -v stat &> /dev/null; then
    # Linux/macOS
    INSTALLED_SIZE=$(stat -c "%s" "${BUILD_TMP}/data.tar.gz" 2>/dev/null || stat -f "%z" "${BUILD_TMP}/data.tar.gz")
elif command -v ls &> /dev/null; then
    # Windows Git Bash/MSYS2
    INSTALLED_SIZE=$(ls -l "${BUILD_TMP}/data.tar.gz" | awk '{print $5}')
else
    echo "Warning: Cannot calculate file size, using default value."
    INSTALLED_SIZE="0"
fi

$SED_CMD "s/^Installed-Size: .*/Installed-Size: ${INSTALLED_SIZE}/g" "${CONTROL_FILE}"

# Create control.tar.gz
echo "Creating control.tar.gz..."
$TAR_CMD -czf "${BUILD_TMP}/control.tar.gz" -C "${TMP_DIR}/CONTROL" --owner 0 --group 0 --sort=name .
if [ $? -ne 0 ]; then
    echo "Error: Failed to create control.tar.gz."
    exit 1
fi

# Create debian-binary file
echo "2.0" > "${BUILD_TMP}/debian-binary"

# Package into final IPK file (actually tar.gz format, but OpenWRT convention uses .ipk extension)
echo "Creating final IPK package..."
$TAR_CMD -czf "${IPK_FILE}" -C "${BUILD_TMP}" --owner 0 --group 0 --sort=name ./debian-binary ./data.tar.gz ./control.tar.gz
if [ $? -ne 0 ]; then
    echo "Error: Failed to create IPK package."
    exit 1
fi

# Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf "${TMP_DIR}"

echo "Build completed!"
echo "IPK package generated: ${IPK_FILE}"

# Display file size
if command -v ls &> /dev/null; then
    if ls -lh "${IPK_FILE}" > /dev/null 2>&1; then
        echo "File size: $(ls -lh "${IPK_FILE}" | awk '{print $5}')"
    else
        echo "Cannot get detailed file size information."
    fi
fi

# Display package information
echo "\nPackage information:"
echo "- Name: ${PACKAGE_NAME}"
echo "- Version: ${PACKAGE_VERSION}"
echo "- Suffix: ${PKG_SUFFIX}"
echo "- Architecture: ${ARCHITECTURE}"
echo "\nNotes:"
echo "1. This script requires Git Bash, Cygwin, or MSYS2 on Windows systems"
echo "2. Ensure necessary tools are installed: tar, sed, awk, etc."
echo "3. For LMO file generation, ensure po2lmo tool is available"

# Final check if file exists
if [ -f "${IPK_FILE}" ]; then
    echo "\n✅ IPK package generated successfully! Ready to install on OpenWRT systems."
else
    echo "\n❌ IPK package generation failed!"
    exit 1
fi