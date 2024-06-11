#!/bin/bash
NAME="omada"
DESC="Omada Controller"

DEST_DIR=/opt/tplink
DEST_FOLDER=EAPController
INSTALLDIR=${DEST_DIR}/${DEST_FOLDER}
DATA_DIR="${INSTALLDIR}/data"
LINK=/etc/init.d/tpeap
LINK_CMD=/usr/bin/tpeap

BACKUP_DIR=${INSTALLDIR}/../omada_db_backup
DB_FILE_NAME=omada.db.tar.gz
INSTALL_PARAM=$1
CONSULT_IMPORT_DB=1

# user confirm
user_confirm() {
    if [ "$INSTALL_PARAM" == "-y" -o "$INSTALL_PARAM" == "-Y" ]; then
        return 0
    fi

    while true
    do
        echo -n "${DESC} will be installed in [${INSTALLDIR}] (y/n): "
        read input
        confirm=`echo $input | tr '[a-z]' '[A-Z]'`

        if [ "$confirm" == "Y" -o "$confirm" == "YES" ]; then
             return 0
        elif [ "$confirm" == "N" -o "$confirm" == "NO" ]; then
             return 1
        fi
    done
}

need_import_mongo_db() {
    if [ "$INSTALL_PARAM" == "-y" -o "$INSTALL_PARAM" == "-Y" ]; then
        return 1
    fi

    while true
    do
        echo -n "${DESC} detects that you have backup previous setting before, will you import it (y/n): "
        read input
        confirm=`echo $input | tr '[a-z]' '[A-Z]'`

        if [ "$confirm" == "Y" -o "$confirm" == "YES" ]; then
            return 1
        elif [ "$confirm" == "N" -o "$confirm" == "NO" ]; then
            return 0
        fi
    done
}

 data_is_empty() {
    # DIR db is existed and not empty.
    if [ -d ${DATA_DIR}/db -a `ls -A ${DATA_DIR}/db | wc -w` -gt 0 ]; then
       echo "data dir is not empty."
       return 0
    fi
    return 1
}



# user confirm
import_mongo_db() {
    data_is_empty
    [ 0 == $? ] && {
        #echo "current data is not empty"
        return
    }

    #echo "current data is empty"

    if test -f ${BACKUP_DIR}/${DB_FILE_NAME}; then
        need_import_mongo_db
        if [ 1 == $? ]; then
            cd  ${BACKUP_DIR}
            tar zxvf ${DB_FILE_NAME} -C ${DATA_DIR}

            rm -rf ${DB_FILE_NAME} > /dev/null 2>&1
            echo "Import previous setting success."
        fi
    fi
}

# return: 0, compatible; 1, not compatible;
version_compatible() {
    to_be_installed_version="Omada Controller v5.13.30.8 for Linux (X64)"
    installed_version=$(${INSTALLDIR}/bin/control.sh version)
    if [[ "$to_be_installed_version" == "Omada Pro Controller"* ]]; then
        if [[ "$installed_version" != "Omada Pro Controller"* ]]; then
          echo "Omada Controller already exists and cannot be upgraded to Omada Pro Controller. If you want to install the Omada Pro Controller, uninstall the current controller first."
          exit
        fi
    else
        if [[ "$installed_version" == "Omada Pro Controller"* ]]; then
            echo "Omada Pro Controller already exists and cannot be downgraded to Omada Controller. If you want to install the ordinary version, uninstall the Pro version first."
            exit
        fi
    fi
    return 0
}

# return: 0, exist; 1, not exist;
dir_exist() {
    if test -d ${INSTALLDIR}
    then
        if test -d ${INSTALLDIR}/jre
        then
            echo "An incompatible controller version has been detected.To upgrade to this new version, please back up configurations of the current version first, and then retry the installation with the current version uninstalled."
            exit
        fi

        dircontent=`ls ${INSTALLDIR}`
        if [ -z "$dircontent" ]; then
            return 0
        fi

        if test -e ${INSTALLDIR}/uninstall.sh
        then
            version_compatible
            echo "An incompatible controller version has been detected. You are strongly recommended to back up configurations of the current version before upgrading. And you can import the configurations after the installation. Input \"Yes\" to continue with upgrade or \"No\" to cancel this upgrade:(y/n):"
            read input
            confirm=`echo $input | tr '[a-z]' '[A-Z]'`

            if [ "$confirm" == "Y" -o "$confirm" == "YES" ]; then
                chown root:root uninstall.sh
                bash ./uninstall.sh upgrade
                CONSULT_IMPORT_DB=0
            elif [ "$confirm" == "N" -o "$confirm" == "NO" ]; then
                exit
            fi
        else
            echo "Your controller is installed by deb. Please uninstall it manually."
            exit
        fi

    fi

    return 1
}

# return: 0, 64 bit; 1, 32 bit;
is64bit() {
    if [ $(getconf WORD_BIT) = '32' ] && [ $(getconf LONG_BIT) = '64' ]
    then
        return 0
    else
        return 1
    fi
}

# return: 0, exist; 1, not exist;
link_exist() {
    if test -x $1; then
        if [ ${INSTALLDIR}/bin/control.sh = $(readlink -f $1) ]; then
          rm $1 -v
            return 1
        else
            return 0
        fi
    else
        return 1
    fi
}


# root permission check
check_root_perms() {
    [ $(id -ru) != 0 ] && { echo "You must be root to install the ${DESC}. Exit." 1>&2; exit 1; }
}

# root permission check
check_root_perms

if ! user_confirm ; then
    exit
fi

echo "======================"
echo "Installation start ..."

# install directory check
if ! dir_exist; then
    mkdir ${INSTALLDIR} -vp > /dev/null
fi


# copy files
for name in bin data properties lib install.sh uninstall.sh
do
    cp ${name} ${INSTALLDIR} -r
done

# config application
link_exist ${LINK}
exist=$?
count=0

while [ $exist -eq 0 ]
do
    count=`expr ${count} + 1`
    link_exist ${LINK}${count}
    exist=$?
done

if [ $count -gt 0 ]; then
    link_name=${LINK}${count}
    link_cmd_name=${LINK_CMD}${count}

else
    link_name=${LINK}
    link_cmd_name=${LINK_CMD}
fi



ln -s ${INSTALLDIR}/bin/control.sh ${link_name}
ln -s ${INSTALLDIR}/bin/control.sh ${link_cmd_name}
ln -sf $(which mongod) ${INSTALLDIR}/bin/mongod


# chmod 755
chmod 755 ${INSTALLDIR}/bin/*

if test -x ${link_name}; then
    update-rc.d $(basename ${link_name}) defaults 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        chkconfig --add ${link_name}
        chkconfig --add ${link_cmd_name}
#       echo "add service with chkconfig"
    fi

    echo "Install ${DESC} succeeded!"
    echo "=========================="

    if [ $CONSULT_IMPORT_DB == 1 ]; then
    import_mongo_db
    fi

    echo "${DESC} will start up with system boot. You can also control it by [${link_cmd_name}]. "

    ${link_name} start

    echo "========================"
    exit
fi

echo "Install ${DESC} failed!"
echo "Roll back ... "

rm -r ${INSTALLDIR}


