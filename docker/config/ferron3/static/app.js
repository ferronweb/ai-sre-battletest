document.addEventListener('DOMContentLoaded', function() {
    var app = document.getElementById('app');
    app.innerHTML = '<p>JavaScript loaded successfully.</p>' +
        '<p>Timestamp: ' + new Date().toISOString() + '</p>';
});
