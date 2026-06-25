'use strict';
'require view';
'require ui';
'require dom';
'require form';
'require uci';
'require poll';
'require rpc';
'require fs';

var callStatus = rpc.declare({
	object: 'wdtt',
	method: 'status'
});

var callLogs = rpc.declare({
	object: 'wdtt',
	method: 'logs',
	params: [ 'tail' ]
});

var callCaptcha = rpc.declare({
	object: 'wdtt',
	method: 'captcha',
	params: [ 'token' ]
});

function formatBytes(n) {
	n = Number(n) || 0;
	if (n < 1024) return n + ' B';
	if (n < 1048576) return (n / 1024).toFixed(1) + ' KiB';
	if (n < 1073741824) return (n / 1048576).toFixed(1) + ' MiB';
	return (n / 1073741824).toFixed(2) + ' GiB';
}

function stateBadge(state) {
	var cls = 'label';
	switch (state) {
	case 'connected': cls += ' success'; break;
	case 'connecting': cls += ' warning'; break;
	case 'captcha_required': cls += ' important'; break;
	case 'error': cls += ' danger'; break;
	default: cls += ' notice';
	}
	return E('span', { 'class': cls }, state || 'unknown');
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('wdtt'),
			callStatus().catch(function() {
				return { running: false, state: 'stopped' };
			})
		]);
	},

	render: function(data) {
		var m, s, o, status = data[1] || {};
		var self = this;

		m = new form.Map('wdtt', _('WDTT VPN'),
			_('WireGuard-туннель через VK TURN/DTLS. Совместим с сервером WDTT/PWDTT.'));

		s = m.section(form.NamedSection, 'globals', 'globals', _('Настройки туннеля'));

		o = s.option(form.Flag, 'enabled', _('Включить'),
			_('Автоматически поднимать туннель при загрузке роутера.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'peer', _('VPS адрес'),
			_('IP или домен сервера с портом, например 203.0.113.10:56000'));
		o.placeholder = '203.0.113.10:56000';
		o.rmempty = false;

		o = s.option(form.Value, 'password', _('Пароль подключения'),
			_('Пароль туннеля с VPS (WRAP-ключ выводится из пароля).'));
		o.password = true;
		o.rmempty = false;

		o = s.option(form.TextValue, 'hashes', _('VK-хеши'),
			_('До 4 хешей через запятую или ссылки vk.com/call/join/...'));
		o.rows = 3;
		o.rmempty = false;

		o = s.option(form.Value, 'workers', _('Потоки'),
			_('Количество воркеров (кратно 3, рекомендуется 6–24 на роутере).'));
		o.datatype = 'uinteger';
		o.default = '12';

		o = s.option(form.Value, 'mtu', 'MTU');
		o.datatype = 'uinteger';
		o.default = '1380';

		o = s.option(form.ListValue, 'captcha_mode', _('Режим капчи'));
		o.value('auto', _('Авто (Go v2)'));
		o.value('rjs', 'RJS');
		o.default = 'auto';

		o = s.option(form.ListValue, 'routing_mode', _('Маршрутизация'),
			_('Selective — как Podkop: только выбранные домены/устройства через WDTT. Full — весь трафик.'));
		o.value('selective', _('Выборочная (Podkop)'));
		o.value('full', _('Полный туннель'));
		o.default = 'selective';

		o = s.option(form.DynamicList, 'routing_excluded_ip', _('Исключить IP'),
			_('Устройства, которые всегда идут напрямую (приоритет выше правил).'));
		o.datatype = 'ipaddr';
		o.placeholder = '192.168.1.100';

		o = s.option(form.Value, 'iface', _('Интерфейс WireGuard'));
		o.default = 'wg-wdtt';
		o.readonly = true;

		/* --- Правила маршрутизации (секции как в Podkop) --- */
		s = m.section(form.TypedSection, 'rule', _('Правила маршрутизации'),
			_('Определяют, какой трафик идёт через WDTT. Работает в режиме «Выборочная».'));
		s.anonymous = false;
		s.addremove = true;

		o = s.option(form.Flag, 'enabled', _('Включено'));
		o.default = '1';

		o = s.option(form.ListValue, 'type', _('Тип'));
		o.value('route', _('В туннель (route)'));
		o.value('exclusion', _('Напрямую (exclusion)'));
		o.default = 'route';

		o = s.option(form.DynamicList, 'domain', _('Домены'),
			_('Например youtube.com — IP добавляется через dnsmasq ipset.'));
		o.placeholder = 'example.com';

		o = s.option(form.DynamicList, 'subnet', _('Подсети'), _('CIDR, например 203.0.113.0/24'));
		o.datatype = 'cidr';
		o.placeholder = '0.0.0.0/0';

		o = s.option(form.DynamicList, 'source_ip', _('IP устройства (полная маршрутизация)'),
			_('Весь трафик этого устройства через WDTT, как fully_routed_ips в Podkop.'));
		o.datatype = 'ipaddr';
		o.placeholder = '192.168.1.50';

		o = s.option(form.Value, 'list_url', _('URL списка доменов'),
			_('Файл: один домен на строку. Загружается при подключении.'));
		o.placeholder = 'https://example.com/list.txt';

		/* --- Статус --- */
		s = m.section(form.NamedSection, 'globals', 'globals', _('Статус'));

		s.render = L.bind(function() {
			return E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Текущее состояние')),
				E('div', { 'id': 'wdtt-status-panel' }, self.renderStatus(status)),
				E('div', { 'class': 'cbi-page-actions' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': ui.createHandlerFn(self, self.handleConnect)
					}, _('Подключить')),
					E('button', {
						'class': 'btn cbi-button cbi-button-reset',
						'click': ui.createHandlerFn(self, self.handleDisconnect)
					}, _('Отключить'))
				])
			]);
		}, s);

		/* --- Логи --- */
		s = m.section(form.NamedSection, 'globals', 'globals', _('Логи'));

		s.render = L.bind(function() {
			return E('div', { 'class': 'cbi-section' }, [
				E('pre', {
					'id': 'wdtt-log-view',
					'style': 'max-height:400px;overflow:auto;font-size:12px;background:#1e1e1e;color:#d4d4d4;padding:12px;border-radius:4px;'
				}, _('Загрузка...'))
			]);
		}, s);

		/* --- Капча --- */
		s = m.section(form.NamedSection, 'globals', 'globals', _('VK Smart Captcha'));

		s.render = L.bind(function() {
			var cap = status.captcha || {};
			return E('div', { 'class': 'cbi-section' }, [
				E('p', {}, cap.required
					? _('Требуется прохождение капчи. Откройте ссылку, решите капчу и вставьте токен.')
					: _('Капча не требуется.')),
				cap.redirect_uri ? E('p', {}, [
					E('a', { 'href': cap.redirect_uri, 'target': '_blank' }, cap.redirect_uri)
				]) : '',
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Токен капчи')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							'id': 'wdtt-captcha-token',
							'type': 'text',
							'style': 'width:100%',
							'placeholder': 'success_token_...'
						}),
						E('button', {
							'class': 'btn cbi-button cbi-button-apply',
							'style': 'margin-top:8px',
							'click': ui.createHandlerFn(self, self.handleCaptcha)
						}, _('Отправить токен'))
					])
				])
			]);
		}, s);

		poll.add(L.bind(this.pollStatus, this), 3);

		return m.render();
	},

	renderStatus: function(st) {
		st = st || {};
		return E('table', { 'class': 'table' }, [
			E('tr', {}, [E('td', { 'width': '200' }, _('Состояние')), E('td', {}, stateBadge(st.state))]),
			E('tr', {}, [E('td', {}, _('Работает')), E('td', {}, st.running ? _('Да') : _('Нет'))]),
			E('tr', {}, [E('td', {}, _('WireGuard')), E('td', {}, st.wg_applied ? _('Поднят') : _('Нет'))]),
			E('tr', {}, [E('td', {}, _('Воркеры')), E('td', {}, String(st.workers || 0))]),
			E('tr', {}, [E('td', {}, _('RX')), E('td', {}, formatBytes(st.rx_bytes))]),
			E('tr', {}, [E('td', {}, _('TX')), E('td', {}, formatBytes(st.tx_bytes))]),
			E('tr', {}, [E('td', {}, _('Uptime')), E('td', {}, (st.uptime_sec || 0) + ' s')]),
			st.last_error ? E('tr', {}, [E('td', {}, _('Ошибка')), E('td', { 'style': 'color:#c00' }, st.last_error)]) : ''
		]);
	},

	pollStatus: function() {
		var self = this;
		return Promise.all([
			callStatus().catch(function() { return {}; }),
			callLogs(150).catch(function() { return { lines: [] }; })
		]).then(function(res) {
			var panel = document.getElementById('wdtt-status-panel');
			if (panel) dom.content(panel, self.renderStatus(res[0]));

			var logView = document.getElementById('wdtt-log-view');
			if (logView) {
				var lines = (res[1] && res[1].lines) || [];
				dom.content(logView, lines.length ? lines.join('\n') : _('Лог пуст'));
			}
		});
	},

	handleConnect: function() {
		return uci.set('wdtt', 'globals', 'enabled', '1')
			.then(function() { return uci.save(); })
			.then(function() { return uci.apply(); })
			.then(function() { return fs.exec('/etc/init.d/wdtt', ['restart']); })
			.then(function() {
				ui.addTimeLimitedNotification(null, E('p', {}, _('Туннель запускается...')), 3000);
			});
	},

	handleDisconnect: function() {
		return uci.set('wdtt', 'globals', 'enabled', '0')
			.then(function() { return uci.save(); })
			.then(function() { return uci.apply(); })
			.then(function() { return fs.exec('/etc/init.d/wdtt', ['stop']); })
			.then(function() {
				ui.addTimeLimitedNotification(null, E('p', {}, _('Туннель остановлен')), 3000);
			});
	},

	handleCaptcha: function() {
		var input = document.getElementById('wdtt-captcha-token');
		var token = input ? input.value : '';
		if (!token) {
			ui.addTimeLimitedNotification(null, E('p', {}, _('Введите токен')), 3000, 'warning');
			return;
		}
		return callCaptcha(token).then(function() {
			ui.addTimeLimitedNotification(null, E('p', {}, _('Токен отправлен')), 3000, 'success');
			if (input) input.value = '';
		});
	}
});
