<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\DutyController;
use App\Http\Controllers\ManifestController;

Route::get('/health', [DutyController::class, 'health']);
Route::post('/duty/calculate', [DutyController::class, 'calculate']);
Route::get('/manifest/{manifestRef}', [ManifestController::class, 'lookup']);

// Failure injection, so the console can break this service without a
// shell. Writes the flag file both controllers read on every request,
// as scripts/php-fail.sh does.
//
// A demo affordance, not a production one. whereIn restricts it to the
// three known modes rather than passing any string to the filesystem.
Route::put('/failmode/{mode}', function (string $mode) {
    file_put_contents('/opt/app/storage/failmode', $mode);
    return ['failMode' => $mode];
})->whereIn('mode', ['on', 'hang', 'off']);
