#!/bin/bash
#
# Author Vitaliy Okulov
# Email vitaliy.okulov@gmail.com
# Скрипт обновляет ядро проекта на базе CMS Drupal


# Задаем корневую директорию где располгается папка проекта.
BASEDIR="SET_ROOT_DIRECTORY_HERE"
# Задаем путь до файла drush.
DRUSHBIN="PATH_TO_DRUSH_BINARY"
# Задаем название симлинка для папки проекта
SMLNAME="NAME_OF_PROJECT_SYMLINK"

cd $BASEDIR
echo "Checking drupal version"
# Получаем номер последней доступной версии CMS Drupal.
output=`$DRUSHBIN dl -s | grep "Project drupal"`
drupaldir="drupal-${output:16:4}"

# Проверяем существует ли директория с новой версией CMS Drupal.
if [ -e $BASEDIR/$drupaldir ]
then
        echo "Error: $drupaldir already exists. Maybe you already did an upgrade?"
        exit 1
fi

cd $BASEDIR
echo "Downloading new drupal"

$DRUSHBIN dl

if [ ! -e $BASEDIR/$drupaldir ]
then
        echo "Error: Drupal directory $BASEDIR/$drupaldir could not be determined correctly"
        exit
fi

# Копируем необходимые файлы в папку с новой версией CMS Drupal.
echo "Copying sites folder and settings to new drupal dir"
cp $BASEDIR/contrib/.htaccess $BASEDIR/$drupaldir
cp $BASEDIR/contrib/php.ini $BASEDIR/$drupaldir
cp -a $BASEDIR/contrib/sites $BASEDIR/$drupaldir
                                                               
# Удаляем симлинк на старую версию CMS Drupal и линкуем новую версию в папку проекта.
echo "Switching link to new drupal"
cd $BASEDIR
rm $SMLNAME
ln -s $drupaldir $SMLNAME
echo "Work complite"
