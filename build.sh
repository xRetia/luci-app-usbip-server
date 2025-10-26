#!/bin/bash
# build.sh - Build luci-app-usbip-server IPK package
# Compatible with ash and bash environments, can run on Linux/OpenWRT or Windows with Git Bash/Cygwin/MSYS2

# Exit on error
set -e

# 定义颜色和格式控制
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
BOLD="\033[1m"

# 输出函数
echo_info() {
    echo -e "${BLUE}${1}${RESET}"
}

echo_success() {
    echo -e "${GREEN}${1}${RESET}"
}

echo_warning() {
    echo -e "${YELLOW}${1}${RESET}"
}

echo_error() {
    echo -e "${RED}${1}${RESET}"
}

echo_header() {
    echo -e "\n${BOLD}${BLUE}${1}${RESET}\n"
}

echo_separator() {
    echo -e "${BLUE}----------------------------------------${RESET}"
}

echo_info "Building luci-app-usbip-server IPK package..."

# 定义变量 - 确保路径格式兼容Windows和Linux
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
IPKG_DIR="${SCRIPT_DIR}/ipkg"
TMP_DIR="${SCRIPT_DIR}/tmp_build"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PO_DIR="${SCRIPT_DIR}/po/zh_Hans"
PO_FILE="${PO_DIR}/usbip_server.po"
LMO_DIR="${TMP_DIR}/usr/lib/lua/luci/i18n"
LMO_FILE="${LMO_DIR}/usbip_server.zh-cn.lmo"

# 定义包信息
PACKAGE_NAME="luci-app-usbip-server"
PACKAGE_VERSION="1.0.1-1"
ARCHITECTURE="all"
PKG_SUFFIX="xretia_dsai"
IPK_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${PKG_SUFFIX}.ipk"

# Create necessary directories
echo_info "Creating temporary directories..."
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${LMO_DIR}"
echo_success "✓ Directories created"

# Create essential directories only
echo_info "Creating essential directories..."
mkdir -p "${TMP_DIR}/etc/config"
mkdir -p "${TMP_DIR}/etc/init.d"
mkdir -p "${TMP_DIR}/etc/uci-defaults"
mkdir -p "${TMP_DIR}/usr/bin"

# Copy files to temporary directory
echo_header "Copying Files"
echo_info "Copying CONTROL directory..."
mkdir -p "${TMP_DIR}/CONTROL"
cp "${IPKG_DIR}/CONTROL/"* "${TMP_DIR}/CONTROL/" 2>/dev/null || echo_warning "Note: CONTROL directory copy may be incomplete"

# Copy configuration files - from files directory
echo_info "Copying configuration files..."
cp -r "${SCRIPT_DIR}/files/etc/"* "${TMP_DIR}/etc/" 2>/dev/null || echo_warning "Note: etc directory copy from files may be incomplete"

# Copy usr files - from files directory
echo_info "Copying usr files..."
cp -r "${SCRIPT_DIR}/files/usr/"* "${TMP_DIR}/usr/" 2>/dev/null || echo_warning "Note: usr directory copy from files may be incomplete"

# Copy view files to correct LuCI location
echo_info "Copying view files..."
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/view/usbip_server"
cp -r "${SCRIPT_DIR}/files/www/luci-static/resources/view/usbip_server/"* "${TMP_DIR}/usr/lib/lua/luci/view/usbip_server/" 2>/dev/null || echo_warning "Note: view files copy may be incomplete"

# Ensure all directories are created
echo_info "Ensuring all required directories exist..."
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/i18n"
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/controller"
mkdir -p "${TMP_DIR}/usr/lib/lua/luci/model/cbi"

# Check if po2lmo command is available
echo_header "Localization Processing"
echo_info "Checking for po2lmo tool..."
if command -v po2lmo &> /dev/null; then
    # Generate lmo file with zh-cn suffix
    echo_info "Generating LMO file with zh-cn suffix..."
    if [ -f "${PO_FILE}" ]; then
        echo_info "  Source: ${PO_FILE}"
        echo_info "  Target: ${LMO_FILE}"
        po2lmo "${PO_FILE}" "${LMO_FILE}"
        if [ $? -ne 0 ]; then
            echo_error "Error: Failed to generate LMO file."
            exit 1
        fi
        echo_success "✓ LMO file generated successfully with zh-cn suffix"
    else
        echo_warning "Warning: PO file not found: ${PO_FILE}"
    fi
else
    echo_warning "Warning: po2lmo command not found. Trying to copy existing lmo file..."
    if [ -f "${IPKG_DIR}/usr/lib/lua/luci/i18n/usbip_server.lmo" ]; then
        cp "${IPKG_DIR}/usr/lib/lua/luci/i18n/usbip_server.lmo" "${LMO_FILE}"
        echo_success "✓ Copied existing LMO file"
    else
        echo_warning "Warning: Cannot generate or find LMO file. IPK package will not contain localization files."
    fi
fi

# Set file permissions
echo_header "Setting Permissions"
echo_info "Setting default file permissions (0644)..."
find "${TMP_DIR}" -type f -exec chmod 644 {} \;

# Set permissions 0755 for shell scripts and executable files
echo_info "Setting executable permissions (0755)..."
find "${TMP_DIR}" -name "*.sh" -exec chmod 755 {} \;
find "${TMP_DIR}" -name "usbip_monitor" -exec chmod 755 {} \;
find "${TMP_DIR}" -name "luci-usbip_server" -exec chmod 755 {} \;

# Set executable permissions for CONTROL scripts (prerm and postinst)
echo_info "Setting CONTROL script permissions..."
chmod 755 "${TMP_DIR}/CONTROL/prerm" "${TMP_DIR}/CONTROL/postinst" 2>/dev/null || true

# Set correct permissions for other CONTROL files
chmod 644 "${TMP_DIR}/CONTROL/control" "${TMP_DIR}/CONTROL/description" 2>/dev/null || true
echo_success "✓ Permissions set successfully"

# Update version and architecture in control file
echo_header "Updating Control File"
echo_info "Preparing control file updates..."
CONTROL_FILE="${TMP_DIR}/CONTROL/control"

# Use Windows-compatible sed syntax
echo_info "Detecting sed command..."
if command -v gsed &> /dev/null; then
    SED_CMD="gsed"
    echo_info "  Using: gsed"
elif command -v sed &> /dev/null; then
    # Check if it's GNU sed (Linux) or BSD sed (macOS)
    if echo "test" | sed -e 's/test/replace/' -i '' 2>/dev/null; then
        # BSD sed (requires empty string parameter)
        SED_CMD="sed -i ''"
        echo_info "  Using: BSD sed"
    else
        # GNU sed
        SED_CMD="sed -i"
        echo_info "  Using: GNU sed"
    fi
else
    echo_error "Error: sed command not found."
    exit 1
fi

# 执行sed命令
echo_info "Updating version and architecture..."
$SED_CMD "s/Version: .*/Version: ${PACKAGE_VERSION}/g" "${CONTROL_FILE}"
$SED_CMD "s/Architecture: .*/Architecture: ${ARCHITECTURE}/g" "${CONTROL_FILE}"
echo_success "✓ Control file updated successfully"

# Create temporary directory for packaging
echo_header "Packaging Preparation"
echo_info "Creating temporary packaging directory..."
BUILD_TMP="${TMP_DIR}/.build_tmp"
mkdir -p "${BUILD_TMP}"
echo "CONTROL" > "${BUILD_TMP}/tarX"
echo_info "  Created exclusion list for tar"

# Set timestamp
TIMESTAMP=$(date)
echo_info "Timestamp: ${TIMESTAMP}"

# Detect available tar command
echo_info "Detecting tar command..."
if command -v gtar &> /dev/null; then
    TAR_CMD="gtar"
    echo_info "  Using: gtar"
elif command -v tar &> /dev/null; then
    TAR_CMD="tar"
    echo_info "  Using: tar"
else
    echo_error "Error: tar command not found."
    exit 1
fi

# Create data.tar.gz
echo_header "Creating Archive Files"
echo_info "Creating data.tar.gz..."
echo_info "  Command: ${TAR_CMD} -X ${BUILD_TMP}/tarX -czf ${BUILD_TMP}/data.tar.gz -C ${TMP_DIR} --owner 0 --group 0 --sort=name ."
$TAR_CMD -X "${BUILD_TMP}/tarX" -czf "${BUILD_TMP}/data.tar.gz" -C "${TMP_DIR}" --owner 0 --group 0 --sort=name .
if [ $? -ne 0 ]; then
    echo_error "Error: Failed to create data.tar.gz."
    exit 1
fi
echo_success "✓ data.tar.gz created successfully"

# Calculate and update Installed-Size
echo_info "Updating Installed-Size..."
if command -v stat &> /dev/null; then
    # Linux/macOS
    INSTALLED_SIZE=$(stat -c "%s" "${BUILD_TMP}/data.tar.gz" 2>/dev/null || stat -f "%z" "${BUILD_TMP}/data.tar.gz")
    echo_info "  Using stat command for file size calculation"
elif command -v ls &> /dev/null; then
    # Windows Git Bash/MSYS2
    INSTALLED_SIZE=$(ls -l "${BUILD_TMP}/data.tar.gz" | awk '{print $5}')
    echo_info "  Using ls command for file size calculation"
else
    echo_warning "Warning: Cannot calculate file size, using default value."
    INSTALLED_SIZE="0"
fi

echo_info "  Installed-Size: ${INSTALLED_SIZE}"
$SED_CMD "s/^Installed-Size: .*/Installed-Size: ${INSTALLED_SIZE}/g" "${CONTROL_FILE}"
echo_success "✓ Installed-Size updated successfully"

# Create control.tar.gz
echo_info "Creating control.tar.gz..."
$TAR_CMD -czf "${BUILD_TMP}/control.tar.gz" -C "${TMP_DIR}/CONTROL" --owner 0 --group 0 --sort=name .
if [ $? -ne 0 ]; then
    echo_error "Error: Failed to create control.tar.gz."
    exit 1
fi
echo_success "✓ control.tar.gz created successfully"

# Create debian-binary file
echo_info "Creating debian-binary file..."
echo "2.0" > "${BUILD_TMP}/debian-binary"
echo_success "✓ debian-binary created successfully"

# Package into final IPK file (actually tar.gz format, but OpenWRT convention uses .ipk extension)
echo_header "Creating Final Package"
echo_info "Creating final IPK package..."
echo_info "  Output file: ${IPK_FILE}"
$TAR_CMD -czf "${IPK_FILE}" -C "${BUILD_TMP}" --owner 0 --group 0 --sort=name ./debian-binary ./data.tar.gz ./control.tar.gz
if [ $? -ne 0 ]; then
    echo_error "Error: Failed to create IPK package."
    exit 1
fi
echo_success "✓ IPK package created successfully"

# Clean up temporary files
echo_header "Cleaning Up"
echo_info "Cleaning up temporary files..."
rm -rf "${TMP_DIR}"
echo_success "✓ Temporary files cleaned up"

echo_separator
echo_success "Build completed!"
echo_success "IPK package generated: ${IPK_FILE}"

# Display file size
echo_header "File Information"
echo_info "Package details:"
if command -v ls &> /dev/null; then
    if ls -lh "${IPK_FILE}" > /dev/null 2>&1; then
        echo_info "  File size: $(ls -lh "${IPK_FILE}" | awk '{print $5}')"
    else
        echo_warning "  Cannot get detailed file size information."
    fi
fi

# Display package information
echo_info "  Name:    ${PACKAGE_NAME}"
echo_info "  Version: ${PACKAGE_VERSION}"
echo_info "  Suffix:  ${PKG_SUFFIX}"
echo_info "  Arch:    ${ARCHITECTURE}"

echo_separator
echo_info "Notes:"
echo_info "  1. This script requires Git Bash, Cygwin, or MSYS2 on Windows systems"
echo_info "  2. Ensure necessary tools are installed: tar, sed, awk, etc."
echo_info "  3. For LMO file generation, ensure po2lmo tool is available"
echo_info "  4. LMO file is generated with zh-cn suffix as required: usbip_server.zh-cn.lmo"

# Final check if file exists
echo_separator
if [ -f "${IPK_FILE}" ]; then
    echo_success "IPK package generated successfully! Ready to install on OpenWRT systems."
else
    echo_error "IPK package generation failed!"
    exit 1
fi