#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DevOps Mastery — PDF & HTML Generator
# Converts all markdown files to PDF (via pandoc) and HTML (standalone)
#
# Prerequisites:
#   Ubuntu/Debian:  sudo apt-get install -y pandoc texlive-xetex texlive-fonts-recommended
#   macOS:          brew install pandoc; brew install --cask mactex
#   OR (no LaTeX):  Use --html-only flag (uses wkhtmltopdf instead)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$ROOT_DIR/PDF-Exports"
HTML_DIR="$ROOT_DIR/HTML-Exports"

HTML_ONLY="${1:-}"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
check_dependencies() {
    if ! command -v pandoc &>/dev/null; then
        error "pandoc not found."
        echo "  Install: sudo apt-get install -y pandoc texlive-xetex texlive-fonts-recommended"
        echo "  macOS:   brew install pandoc && brew install --cask mactex"
        exit 1
    fi

    if [[ "$HTML_ONLY" != "--html-only" ]]; then
        if ! pandoc --version 2>&1 | grep -q "pdf"; then
            warn "pandoc PDF engine (xelatex) may not be available."
            warn "Run with --html-only to skip PDF and generate HTML only."
        fi
    fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────
setup_dirs() {
    mkdir -p "$OUTPUT_DIR" "$HTML_DIR"
    info "Output dirs: $OUTPUT_DIR | $HTML_DIR"
}

# ── CSS for HTML export ───────────────────────────────────────────────────────
write_css() {
    cat > /tmp/devops-style.css << 'CSSEOF'
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    max-width: 1100px;
    margin: 0 auto;
    padding: 20px 40px;
    color: #24292e;
    line-height: 1.6;
}
h1 { color: #0366d6; border-bottom: 2px solid #0366d6; padding-bottom: 8px; }
h2 { color: #24292e; border-bottom: 1px solid #e1e4e8; padding-bottom: 4px; }
h3 { color: #444; }
code {
    background: #f6f8fa;
    padding: 2px 6px;
    border-radius: 3px;
    font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
    font-size: 0.9em;
}
pre {
    background: #1e1e1e;
    color: #d4d4d4;
    padding: 16px;
    border-radius: 6px;
    overflow-x: auto;
    font-size: 0.88em;
    line-height: 1.5;
}
pre code {
    background: none;
    color: inherit;
    padding: 0;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin: 16px 0;
}
th, td {
    border: 1px solid #e1e4e8;
    padding: 8px 12px;
    text-align: left;
}
th { background: #f6f8fa; font-weight: 600; }
tr:nth-child(even) { background: #f9f9f9; }
blockquote {
    border-left: 4px solid #0366d6;
    margin: 0;
    padding: 8px 16px;
    background: #f1f8ff;
    color: #555;
}
a { color: #0366d6; }
hr { border: 0; border-top: 1px solid #e1e4e8; margin: 24px 0; }
CSSEOF
}

# ── Convert single file ───────────────────────────────────────────────────────
convert_file() {
    local md_file="$1"
    local relative_path="${md_file#$ROOT_DIR/}"
    local base_name
    base_name=$(basename "$md_file" .md)
    local parent_dir
    parent_dir=$(dirname "$relative_path" | tr '/' '-' | sed 's/^-//')

    local output_base="$parent_dir-$base_name"
    [[ "$parent_dir" == "." ]] && output_base="$base_name"

    local html_out="$HTML_DIR/${output_base}.html"
    local pdf_out="$OUTPUT_DIR/${output_base}.pdf"

    # Generate HTML
    pandoc "$md_file" \
        --standalone \
        --css=/tmp/devops-style.css \
        --metadata title="DevOps Mastery: $base_name" \
        --highlight-style=tango \
        --toc \
        --toc-depth=3 \
        -o "$html_out" 2>/dev/null \
        && info "HTML: ${output_base}.html" \
        || warn "HTML failed: $md_file"

    # Generate PDF (skip if html-only or no xelatex)
    if [[ "$HTML_ONLY" != "--html-only" ]]; then
        pandoc "$md_file" \
            --pdf-engine=xelatex \
            --variable geometry:margin=1.2cm \
            --variable fontsize=10pt \
            --variable colorlinks=true \
            --variable linkcolor=blue \
            --variable mainfont="DejaVu Sans" \
            --variable monofont="DejaVu Sans Mono" \
            --highlight-style=tango \
            --toc \
            -o "$pdf_out" 2>/dev/null \
            && info "PDF:  ${output_base}.pdf" \
            || warn "PDF failed (missing LaTeX?): $md_file — run with --html-only"
    fi
}

# ── Generate combined master PDF ──────────────────────────────────────────────
generate_master_pdf() {
    info "Building master combined PDF..."
    local master_file="/tmp/devops-master.md"

    # Header
    cat > "$master_file" << 'HEADEREOF'
---
title: "DevOps Mastery — Complete Study Guide"
subtitle: "Scratch to Senior Level"
author: "DevOps Engineer"
date: \today
toc: true
toc-depth: 3
---

HEADEREOF

    # Append all markdown files in logical order
    local ordered_dirs=(
        "00-Learning-Path"
        "01-Linux-Fundamentals"
        "02-Networking"
        "03-Git-Version-Control"
        "04-CI-CD"
        "05-Docker-Containers"
        "06-Kubernetes"
        "07-Infrastructure-as-Code"
        "08-Cloud-Platforms"
        "09-Monitoring-Observability"
        "10-Security-DevSecOps"
        "11-SRE-Practices"
        "Brain-Maps"
        "Cheatsheets"
        "Interview-Prep"
    )

    for dir in "${ordered_dirs[@]}"; do
        local dir_path="$ROOT_DIR/$dir"
        if [[ -d "$dir_path" ]]; then
            echo -e "\n\n\\newpage\n# ${dir}\n" >> "$master_file"
            while IFS= read -r -d '' f; do
                echo -e "\n---\n" >> "$master_file"
                cat "$f" >> "$master_file"
            done < <(find "$dir_path" -name "*.md" -print0 | sort -z)
        fi
    done

    if [[ "$HTML_ONLY" != "--html-only" ]]; then
        pandoc "$master_file" \
            --pdf-engine=xelatex \
            --variable geometry:margin=1.2cm \
            --variable fontsize=10pt \
            --variable colorlinks=true \
            --variable linkcolor=blue \
            --highlight-style=tango \
            --toc \
            -o "$OUTPUT_DIR/DevOps-Mastery-Complete.pdf" 2>/dev/null \
            && info "Master PDF: DevOps-Mastery-Complete.pdf" \
            || warn "Master PDF failed. Try: --html-only"
    fi

    pandoc "$master_file" \
        --standalone \
        --css=/tmp/devops-style.css \
        --highlight-style=tango \
        --toc \
        --toc-depth=4 \
        -o "$HTML_DIR/DevOps-Mastery-Complete.html" 2>/dev/null \
        && info "Master HTML: DevOps-Mastery-Complete.html"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    info "Export complete!"
    echo ""
    echo "  HTML files: $HTML_DIR"
    echo "  PDF files:  $OUTPUT_DIR"
    echo ""
    local html_count pdf_count
    html_count=$(find "$HTML_DIR" -name "*.html" 2>/dev/null | wc -l | tr -d ' ')
    pdf_count=$(find "$OUTPUT_DIR" -name "*.pdf" 2>/dev/null | wc -l | tr -d ' ')
    echo "  HTML: $html_count files"
    echo "  PDF:  $pdf_count files"
    echo ""
    echo "  Open master guide:"
    echo "  xdg-open $HTML_DIR/DevOps-Mastery-Complete.html"
    [[ -f "$OUTPUT_DIR/DevOps-Mastery-Complete.pdf" ]] && \
        echo "  xdg-open $OUTPUT_DIR/DevOps-Mastery-Complete.pdf"
    echo "═══════════════════════════════════════════════════════════"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║  DevOps Mastery — PDF/HTML Generator  ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo ""

    [[ "$HTML_ONLY" == "--html-only" ]] && \
        warn "HTML-only mode — skipping PDF generation"

    check_dependencies
    setup_dirs
    write_css

    # Convert individual files
    while IFS= read -r -d '' md_file; do
        [[ "$(basename "$md_file")" == "README.md" ]] && continue
        convert_file "$md_file"
    done < <(find "$ROOT_DIR" \
        -name "*.md" \
        -not -path "*/\.*" \
        -not -path "*/node_modules/*" \
        -print0 | sort -z)

    # Build combined master document
    generate_master_pdf
    print_summary
}

main
