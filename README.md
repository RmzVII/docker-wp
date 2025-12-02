README.md
## 1. Встановлення WSL2
1. Відкрити PowerShell від імені адміністратора та виконати:
'''
wsl –-install ubuntu
'''
2. Перезавантажити комп’ютер.
3. Клонування репозиторію
Відкрити Ubuntu і виконати:
'''
git clone https://github.com/RmzVII/docker-wp ~/wpmanager
cd ~/wpmanager
'''
________________________________________
3. Встановлення WordPress Manager. виконати команду:
bash install.sh
echo $PATH

Запуск
'''
bash ~/.local/bin/wpmanager 
'''
⚠ Якщо це перший запуск — потрібно перезапустити WSL:
'''
wsl --shutdown
'''
________________________________________

створення сімлінка
'''
sudo ln -sf ~/wpmanager/wpmanager.sh /usr/local/bin/wpmanager
sudo chmod +x ~/wpmanager/wpmanager.sh
sudo chmod +x /usr/local/bin/wpmanager
'''
