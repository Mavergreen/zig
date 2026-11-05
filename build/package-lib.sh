# platform: macOS-only -- ditto copies the stage without the extended attributes macOS stamps on it
#   usage: . build/package-lib.sh; package_variant native|cross     packages the staged zig (native: build-native.sh's
#          x86_64 10.9 zig; cross: build-host-zig.sh's arm64 zig-cross) with its updater into dist/<short>-<FULL>.pkg,
#          and records dist/build-info-<variant>.txt. variant_requires VARIANT prints the products its pkg requires.
# spec: PORT.md 0002-macos-x86_64-pinned-sdk.patch -- both trees link SDKs to ../sdk109/SDKs and every 10.9 target
#       compiles against that SDK, so each preinstall refuses a volume without sdk109
variant_requires() { case "$1" in native|cross) echo sdk109 ;; esac; }
package_variant() {
  v="$1"
  ZIG_VARIANT="$v"; export ZIG_VARIANT
  . "$REPO_ROOT/build/versions.sh"; . "$REPO_ROOT/build/lib-zig.sh"
  export COPYFILE_DISABLE=1
  case "$v" in
    native) short="$NATIVE_SHORT"; prefix="$NATIVE_PREFIX"; sroot="$NATIVE_STAGE_ROOT"
            arch=x86_64; floor="--min-os 10.9.5 --host-arch x86_64"; title_tail="" ;;
    cross)  short="$CROSS_SHORT"; prefix="$CROSS_PREFIX"; sroot="$CROSS_STAGE_ROOT"
            arch=arm64; floor="--min-os 11.0 --host-arch arm64"; title_tail=" (cross toolchain for modern macOS)" ;;
    *) echo "package_variant: native|cross (got '$v')" >&2; return 2 ;;
  esac
  id="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" identifier "$short")" \
    || { echo "FATAL: $short is not in shipyard's scripts/product-names" >&2; exit 1; }
  st="$sroot$prefix"
  [ "$v" = native ] && builder=build-native.sh || builder=build-host-zig.sh
  [ -x "$st/bin/zig" ] && [ -d "$st/lib/zig/std" ] && [ -d "$st/lib/mavergreen" ] \
    || { echo "FATAL: $v not staged at $st (run build/$builder on $arch)" >&2; exit 1; }
  [ -z "${RECAULK_LIB:-}" ] \
    || { echo "FATAL: RECAULK_LIB is set; a stage built with an unreleased Recaulk is never packaged: unset it and rebuild with build/$builder on $arch" >&2; exit 1; }
  want="$(build_info "$v")" || exit 1
  grep -qxF "$want" "$st/lib/mavergreen/BUILD-INFO" 2>/dev/null \
    || { echo "FATAL: $st holds a zig $builder did not build from this checkout (lib/mavergreen/BUILD-INFO must be '$want', it is '$(cat "$st/lib/mavergreen/BUILD-INFO" 2>/dev/null)'): rebuild with build/$builder on $arch" >&2; exit 1; }
  VER="$(sh "$SHIPYARD_SCRIPTS/resolve-version.sh" "$(sh "$SHIPYARD_SCRIPTS/release-mode.sh")")"
  pr="$WORK/pkgroot"; scr="$WORK/pkg-scripts"; comp="$WORK/$short-component.pkg"
  rm -rf "$pr" "$scr"; mkdir -p "$pr$(dirname "$prefix")" "$REPO_ROOT/dist"
  # platform: macOS stamps an undeletable com.apple.provenance on every file a tracked process
  #           writes; --noextattr keeps every extended attribute out of the copied payload
  ditto --norsrc --noextattr --noacl "$st" "$pr$prefix"
  app="$(sh "$REPO_ROOT/build/build-updater.sh" "$v")"
  set -- --stage "$pr" --product "$short" --name "Zig for Mavericks" --group zig \
    --version "$VER" --scripts-out "$scr" --updater-app "$app"
  for _r in $(variant_requires "$v"); do set -- "$@" --requires "$_r"; done
  find "$pr" -name '._*' -delete
  sh "$SHIPYARD_SCRIPTS/stage_product.sh" "$@"
  sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" --root "$pr" --identifier "$id" --version "$VER" \
    --scripts "$scr" --install-location / --out "$comp" >/dev/null
  out="$REPO_ROOT/dist/$short-$VER.pkg"
  sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" --identifier "$id" \
    --title "Zig for Mavericks $VER$title_tail" --component "$comp" --out "$out" $floor --require-scripts
  rm -f "$comp"
  sh "$SHIPYARD_SCRIPTS/build-info.sh" "$REPO_ROOT/dist/build-info-$v.txt" \
    variant="$v" arch="$arch" prefix="$prefix" pkg="$(basename "$out")" identifier="$id" \
    zig="$ZIG_VERSION" llvm="${CLANG_VERSION%%-*}" clang22="$CLANG_VERSION" recaulk="$RECAULK_VERSION"
  echo "built $out"
}
