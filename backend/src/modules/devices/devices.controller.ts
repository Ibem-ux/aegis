import { FastifyReply, FastifyRequest } from 'fastify';
import { DevicesService } from './devices.service';
import { ApproveDeviceBody } from './devices.types';
import { UnauthorizedError, BadRequestError } from '../../utils/errors';

export class DevicesController {
  public static async list(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const devices = await DevicesService.getUserDevices(request.server.db, user.userId);
    return reply.status(200).send(devices);
  }

  public static async approve(
    request: FastifyRequest<{ Body: ApproveDeviceBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string; deviceId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const { device_id } = request.body;

    if (device_id === user.deviceId) {
      throw new BadRequestError('Cannot approve yourself');
    }

    const device = await DevicesService.approveDevice(
      request.server.db,
      user.userId,
      device_id,
      user.deviceId
    );

    return reply.status(200).send({
      message: 'Device trust established successfully',
      device
    });
  }

  public static async remove(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string; deviceId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const targetDeviceId = request.params.id;

    if (targetDeviceId === user.deviceId) {
      throw new BadRequestError('Cannot remove current device session');
    }

    await DevicesService.removeDevice(request.server.db, user.userId, targetDeviceId);
    return reply.status(200).send({
      message: 'Device successfully removed'
    });
  }
}
