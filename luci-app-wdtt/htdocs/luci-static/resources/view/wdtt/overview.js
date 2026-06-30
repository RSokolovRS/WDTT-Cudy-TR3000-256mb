'use strict';
'require view';
'require ui';
'require dom';
'require form';
'require uci';
'require poll';
'require rpc';

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

var callConnect = rpc.declare({
	object: 'wdtt',
	method: 'connect'
});

var callDisconnect = rpc.declare({
	object: 'wdtt',
	method: 'disconnect'
});

var callApplyConfig = rpc.declare({
	object: 'wdtt',
	method: 'apply_config'
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

function wdttPageTitle(status) {
	var v = String((status && status.package_version) || '').replace(/^v/i, '').trim();
	return v ? _('WDTT VPN') + ' v' + v : _('WDTT VPN');
}

function normalizeDomainList(val) {
	if (val == null || val === '')
		return '';

	return String(val).replace(/\r/g, '').split(/[\n,;]+/).map(function(d) {
		d = d.trim().replace(/^https?:\/\//i, '').split('/')[0].split(' ')[0].toLowerCase();
		return d;
	}).filter(function(d) {
		return d && d.indexOf('.') !== -1 && d.indexOf('2iw') === -1 && d.indexOf('yoltlbe') === -1;
	}).filter(function(d, i, a) {
		return a.indexOf(d) === i;
	}).join(',');
}

function wdttPageDescription(status) {
	var lines = [_('WireGuard-туннель через VK TURN/DTLS. Совместим с сервером WDTT/PWDTT.')];
	var wdttd = String((status && status.wdttd_version) || '').trim();
	if (wdttd) {
		lines.push(_('Демон wdttd:') + ' ' + wdttd);
	}
	return lines.join(' ');
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

		m = new form.Map('wdtt', wdttPageTitle(status), wdttPageDescription(status));

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

		o = s.option(form.ListValue, 'captcha_mode', _('Режим капчи'),
			_('Auto/RJS — роутер решает капчу сам. WV — вы открываете ссылку в браузере и вставляете success_token (рекомендуется после лимита VK).'));
		o.value('auto', _('Авто (Go v2 + fallback)'));
		o.value('rjs', _('RJS (только авто Go v2)'));
		o.value('wv', _('WV (ручной — ссылка + токен)'));
		o.default = 'wv';

		o = s.option(form.ListValue, 'vk_auth_mode', _('Режим VK Auth'),
			_('VKCalls — получение TURN-кредов через anonymous flow (без капчи, рекомендуется). Legacy — старый путь через calls.getAnonymousToken с капчей.'));
		o.value('vkcalls', _('VKCalls (без капчи)'));
		o.value('legacy', _('Legacy (капча)'));
		o.default = 'vkcalls';

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

		o = s.option(form.TextValue, 'domain_list', _('Домены'),
			_('Через запятую или с новой строки. Сохраняется одной строкой UCI. Пример: youtube.com, googlevideo.com'));
		o.rows = 4;
		o.placeholder = 'youtube.com, googlevideo.com, 2ip.ru';
		o.rmempty = true;
		o.load = function(section_id) {
			var v = uci.get('wdtt', section_id, 'domain_list');
			if (v == null)
				return '';
			if (Array.isArray(v))
				v = v.join(',');
			return String(v).replace(/,/g, '\n');
		};
		o.write = function(section_id, formvalue) {
			var normalized = normalizeDomainList(formvalue);
			if (normalized)
				uci.set('wdtt', section_id, 'domain_list', normalized);
			else
				uci.unset('wdtt', section_id, 'domain_list');
		};
		o.remove = function(section_id) {
			uci.unset('wdtt', section_id, 'domain_list');
		};

		o = s.option(form.DynamicList, 'subnet', _('Подсети'), _('CIDR, например 203.0.113.0/24'));
		o.datatype = 'cidr';
		o.placeholder = '203.0.113.0/24';
		o.rmempty = true;

		o = s.option(form.DynamicList, 'source_ip', _('IP устройства (полная маршрутизация)'),
			_('Весь трафик этого устройства через WDTT, как fully_routed_ips в Podkop.'));
		o.datatype = 'ipaddr';
		o.placeholder = '192.168.1.50';

		o = s.option(form.Value, 'list_url', _('URL списка доменов'),
			_('Файл: один домен на строку. Загружается при подключении.'));
		o.placeholder = 'https://example.com/list.txt';
		o.rmempty = true;

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
			return E('div', { 'class': 'cbi-section', 'id': 'wdtt-captcha-panel' },
				self.renderCaptchaPanel(status.captcha || {}));
		}, s);

		poll.add(L.bind(this.pollStatus, this), 3);

		var mapSave = m.save.bind(m);
		m.save = function() {
			return mapSave().then(function() {
				return callApplyConfig().catch(function() { return {}; });
			});
		};

		return m.render();
	},

	renderCaptchaPanel: function(cap) {
		cap = cap || {};
		var uri = cap.redirect_uri || '';
		var nodes = [
			E('h3', {}, _('VK Smart Captcha')),
			E('p', {}, cap.required
				? _('Требуется капча VK. Ссылка живёт ~1–2 минуты — при ошибке нажмите «Подключить» снова.')
				: _('Капча не требуется.'))
		];

		if (uri) {
			nodes.push(
				E('p', { 'class': 'hint' },
					_('Если ссылка не открывается: скопируйте URL, откройте на телефоне с мобильным интернетом (не через роутер).')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Ссылка на капчу')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('textarea', {
							'id': 'wdtt-captcha-url',
							'readonly': 'readonly',
							'rows': 3,
							'style': 'width:100%;font-family:monospace;font-size:12px;'
						}, uri),
						E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top:8px' }, [
							E('button', {
								'class': 'btn cbi-button cbi-button-action',
								'click': ui.createHandlerFn(this, this.handleOpenCaptcha)
							}, _('Открыть в новой вкладке')),
							E('button', {
								'class': 'btn cbi-button cbi-button-save',
								'click': ui.createHandlerFn(this, this.handleCopyCaptchaUrl)
							}, _('Копировать URL'))
						])
					])
				])
			);
		}

		nodes.push(
			E('p', { 'class': 'hint' },
				_('После решения капчи: F12 → Network → captchaNotRobot.check → success_token в ответе.')),
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
						'click': ui.createHandlerFn(this, this.handleCaptcha)
					}, _('Отправить токен'))
				])
			])
		);

		return nodes;
	},

	renderStatus: function(st) {
		st = st || {};
		var pkgVer = String(st.package_version || '').trim();
		var wdttdVer = String(st.wdttd_version || st.version || '').trim();
		return E('table', { 'class': 'table' }, [
			pkgVer ? E('tr', {}, [E('td', { 'width': '200' }, _('Версия WDTT')), E('td', {}, pkgVer)]) : '',
			wdttdVer ? E('tr', {}, [E('td', {}, _('Демон wdttd')), E('td', {}, wdttdVer)]) : '',
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

			var capPanel = document.getElementById('wdtt-captcha-panel');
			if (capPanel && res[0] && res[0].state === 'captcha_required') {
				var cap = res[0].captcha || {};
				var ta = document.getElementById('wdtt-captcha-url');
				if (cap.redirect_uri && (!ta || ta.value !== cap.redirect_uri)) {
					dom.content(capPanel, self.renderCaptchaPanel(cap));
				}
			}
		});
	},

	handleOpenCaptcha: function() {
		var ta = document.getElementById('wdtt-captcha-url');
		var uri = ta ? ta.value.trim() : '';
		if (!uri) {
			ui.addTimeLimitedNotification(null, E('p', {}, _('Ссылка пуста — нажмите «Подключить» для новой капчи')), 4000, 'warning');
			return;
		}
		window.open(uri, '_blank', 'noopener,noreferrer');
	},

	handleCopyCaptchaUrl: function() {
		var ta = document.getElementById('wdtt-captcha-url');
		var uri = ta ? ta.value.trim() : '';
		if (!uri) {
			ui.addTimeLimitedNotification(null, E('p', {}, _('Нечего копировать')), 3000, 'warning');
			return;
		}
		if (ta) {
			ta.focus();
			ta.select();
		}
		try {
			document.execCommand('copy');
			ui.addTimeLimitedNotification(null, E('p', {}, _('URL скопирован')), 2000, 'success');
		} catch (e) {
			ui.addTimeLimitedNotification(null, E('p', {}, _('Выделите URL и скопируйте вручную (Ctrl+C)')), 4000, 'warning');
		}
	},

	syncEnabledFlag: function(value) {
		uci.set('wdtt', 'globals', 'enabled', value);
		var el = document.querySelector('[data-widget-id="wdtt.globals.enabled"] input[type="checkbox"]')
			|| document.querySelector('input[name="cbid.wdtt.globals.enabled"]');
		if (el) {
			el.checked = (value === '1');
		}
	},

	handleConnect: function() {
		var self = this;
		return callConnect().then(function(res) {
			if (res && res.error) {
				throw new Error(res.error);
			}
			self.syncEnabledFlag('1');
			ui.addTimeLimitedNotification(null, E('p', {}, _('Туннель запускается...')), 3000);
			return self.pollStatus();
		}).catch(function(e) {
			ui.addTimeLimitedNotification(null, E('p', {}, e.message || String(e)), 5000, 'danger');
		});
	},

	handleDisconnect: function() {
		var self = this;
		return callDisconnect().then(function(res) {
			if (res && res.error) {
				throw new Error(res.error);
			}
			self.syncEnabledFlag('0');
			ui.addTimeLimitedNotification(null, E('p', {}, _('Туннель остановлен')), 3000);
			return self.pollStatus();
		}).catch(function(e) {
			ui.addTimeLimitedNotification(null, E('p', {}, e.message || String(e)), 5000, 'danger');
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
