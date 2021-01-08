#!/bin/bash

yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
gre='\e[0;32m'
ZIMG=./out/arch/arm64/boot/Image.gz-dtb

disable_mkclean=false
mkdtbs=false
oc_flag=false
more_uv_flag=false
campatch_flag=false
anykernel_build=false
SPAM_TELEGRAM=true

if [ -z "$TELEGRAM_TOKEN" ] && [ -z "$TELEGRAM_CHAT" ] && [ -n "$SPAM_TELEGRAM"]; then
	echo "Please set TELEGRAM_TOKEN and TELEGRAM_CHAT variables"
	exit 1
fi

for arg in $@; do
	case $arg in
		"--noclean") disable_mkclean=true;;
		"--dtbs") mkdtbs=true;;
		"-oc") oc_flag=true;;
		"-80uv") more_uv_flag=true;;
		"-campatch") campatch_flag=true;;
		"-anykernel") anykernel_build=true;;
		*) {
        cat <<EOF
Usage: $0 <operate>
operate:
    --noclean   : build without run "make mrproper"
    --dtbs      : build dtbs only
    -oc         : build with apply Overclock patch
    -80uv       : build with apply 80mv UV patch
    -campatch   : build with apply camera fix patch
	-anykernel  : build with anykernel autopacking
EOF
        exit 1
        };;
	esac
done

export LOCALVERSION=-v1.0

rm -f $ZIMG

export ARCH=arm64
export SUBARCH=arm64
export HEADER_ARCH=arm64
export SPAM_TELEGRAM=true
export EAS_KERNEL=false
export CLANG_PATH=/home/$(whoami)/toolchains/proton-clang
export KBUILD_COMPILER_STRING=$($CLANG_PATH/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "panda-qrebase-eas" ]]; then
	export EAS_KERNEL=true
fi

export KBUILD_BUILD_HOST=`hostname`
export KBUILD_BUILD_USER=`whoami`

ccache_=`which ccache`

$oc_flag && { git apply ./oc.patch || exit 1; }
$more_uv_flag && { git apply ./80mv_uv.patch || exit 1; }
$campatch_flag && { git apply ./campatch.patch || exit 1; }

$disable_mkclean || make mrproper O=out || exit 1
make whyred-perf_defconfig O=out || exit 1

[[ $SPAM_TELEGRAM == true ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=* CxckKernel build started!*

Info:
Only-dtbs build: $mkdtbs
Overclocking: $oc_flag
EAS: $EAS_KERNEL
Camera patch: $campatch_flag
Undervolting: $more_uv_flag
AnyKernel3 Packaging: $anykernel_build" >/dev/null

ZIPNAME="CxckKernel-whyred"

if $oc_flag; then
	ZIPNAME+="-OC"
fi

if $EAS_KERNEL; then
	ZIPNAME+="-EAS"
fi
if $more_uv_flag; then
	ZIPNAME+="-UV"
fi
ZIPNAME+="-$(date '+%Y%m%d').zip"

Start=$(date +"%s")

$mkdtbs && make_flag="dtbs" || make_flag=""

make $make_flag -j6 \
	O=out \
	CC="${ccache_} ${CLANG_PATH}/bin/clang" \
	CLANG_TRIPLE=aarch64-linux-gnu- \
	CROSS_COMPILE="${CLANG_PATH}/bin/aarch64-linux-gnu-" \
	CROSS_COMPILE_ARM32="${CLANG_PATH}/bin/arm-linux-gnueabi-"

exit_code=$?
End=$(date +"%s")
Diff=$(($End - $Start))

$oc_flag && { git apply -R ./oc.patch || exit 1; }
$more_uv_flag && { git apply -R ./80mv_uv.patch || exit 1; }
$campatch_flag && { git apply -R ./campatch.patch || exit 1; }

if $mkdtbs; then
	if [ $exit_code -eq 0 ]; then
		echo -e "$gre << Build completed >> \n $white"
	else
		echo -e "$red << Failed to compile dtbs, fix the errors first >>$white"
		exit $exit_code
	fi
else
	[[ $SPAM_TELEGRAM == true ]] && [[ $anykernel_build != true ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=* CxckKernel build passed!*\nTook: $(($Diff / 60)) minutes and $(($Diff % 60)) seconds" >/dev/null
	if $anykernel_build; then
		if [ -f $ZIMG ]; then
			echo "Building with AnyKernel3..."
			git clone https://github.com/cockroms-stuff/AnyKernel3 -b cxck-whyred
			cd AnyKernel3
			cp $ZIMG ./
			zip -r9 "../out/$ZIPNAME" * -x '*.git*' README.md *placeholder
			cd .. && rm -rf AnyKernel3
			[[ $SPAM_TELEGRAM == true ]] && curl -s -F "chat_id=$TELEGRAM_CHAT" -F "parse_mode=Markdown" -F "caption=* CxckKernel build passed!*
Took: $(($Diff / 60)) minutes and $(($Diff % 60)) seconds" -F document=@out/$ZIPNAME https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null
			echo -e "$gre << Build completed in $(($Diff / 60)) minutes and $(($Diff % 60)) seconds >> \n $white"
			rm -rf out/$ZIPNAME
		else
			[[ $SPAM_TELEGRAM == true ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=* CxckKernel build failed!*
Unable to find Image.gz-dtb
Check console for more info!" >/dev/null
			echo -e "$red << Failed to compile Image.gz-dtb, fix the errors first >>$white"
			exit $exit_code
		fi
	else
		if [ -f $ZIMG ]; then
			echo -e "$gre << Build completed in $(($Diff / 60)) minutes and $(($Diff % 60)) seconds >> \n $white"
		else
			echo -e "$red << Failed to compile Image.gz-dtb, fix the errors first >>$white"
			exit $exit_code
		fi
	fi
fi

